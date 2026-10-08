# Deploy theo từng bước trong CloudShell

Trạng thái: cấu hình tạo hạ tầng đã chuyển sang LabRole; chưa tạo tài nguyên AWS. Ứng dụng gốc vẫn cần giải quyết IRSA, CSI, secrets và NetworkPolicy trước khi sync.

## Đọc để hiểu luồng

1. `terraform/learner-lab.tfvars`: account, region, role có sẵn và số node.
2. `terraform/main.tf`: nối các module; cấu hình Lab không chạy IAM, IRSA và Helm.
3. `terraform/modules/networking/main.tf`: VPC, subnet, route và NAT.
4. `terraform/modules/eks/main.tf`: cluster, managed node group, launch template.
5. `.github/workflows/ci.yaml`: kiểm tra Go và Kubernetes.
6. `.github/workflows/app-cd.yaml`: build 9 image → scan → push ECR → commit tag vào Deployment.
7. `kubernetes/argocd/root-app.yaml`, `kubernetes/argocd/apps/*.yaml`: Argo đọc Git và đồng bộ resource vào cluster.
8. Một `kubernetes/application/*/deployment.yaml`: image, replicas, env, probes, resource; `service.yaml`: cách các Pod được truy cập.
9. `kubernetes/database`: PostgreSQL/Redis và yêu cầu storage/secrets.

Terraform tạo máy và mạng. GitHub Actions tạo image. Argo CD lấy manifest từ Git để chạy image trên máy đó. Workflow infrastructure hiện chỉ validate, chưa apply.

## 1. Đưa thay đổi lên Git

Trên máy của bạn, review `git diff`, commit và push những thay đổi cần dùng. Không commit credentials, terraform state hay plan. File learner-lab.tfvars chỉ chứa cấu hình không bí mật và được phép commit.

Trong CloudShell Bash:

```bash
git clone https://github.com/anhhao1712/eks-project1.git
cd eks-project1
```

Nếu đã clone: vào thư mục và chạy `git pull --ff-only`. Repo private cần xác thực Git; không dán token vào chat.

## 2. Terraform và nơi lưu state

```bash
terraform version
```

Nếu chưa có Terraform, cài bản 1.13.5 từ HashiCorp (CloudShell x86_64):

```bash
mkdir -p "$HOME/bin"
curl -fLO https://releases.hashicorp.com/terraform/1.13.5/terraform_1.13.5_linux_amd64.zip
curl -fLO https://releases.hashicorp.com/terraform/1.13.5/terraform_1.13.5_SHA256SUMS
grep 'terraform_1.13.5_linux_amd64.zip$' terraform_1.13.5_SHA256SUMS | sha256sum -c -
```

Chỉ khi checksum OK mới chạy:

```bash
unzip -o terraform_1.13.5_linux_amd64.zip -d "$HOME/bin"
export PATH="$HOME/bin:$PATH"
```

Chọn tên bucket state duy nhất, ghi lại để dùng cho mọi lần sau. Nếu đã có bucket state thì dùng bucket đó, không tạo lại.

```bash
STATE_BUCKET="eks-project1-tfstate-425959969184-$(date +%s)"
echo "$STATE_BUCKET"
aws s3api create-bucket --bucket "$STATE_BUCKET" --region us-east-1
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$STATE_BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
cd terraform
terraform init -backend-config="bucket=$STATE_BUCKET"
terraform validate
terraform plan -var-file=learner-lab.tfvars -out=lab.tfplan
```

Xem plan: IAM role/policy/OIDC và Helm phải bằng 0 resource được tạo. Có VPC 3 AZ, NAT của tác giả, EKS, 2 node t3.medium ban đầu, 9 ECR repo, SQS, security group và secret database_url chưa có giá trị. Hai node là điểm khởi đầu, chưa bảo đảm đủ cho toàn bộ app/monitoring.

Nếu plan lỗi repo ECR hoặc tên tài nguyên đã tồn tại, dừng và import resource đúng vào state; không xóa tài nguyên hiện có. Nếu quyền AWS bị từ chối, gửi lỗi để xử lý đúng resource. Không dùng `-target` để bỏ qua lỗi.

Khi plan đúng, tạo tài nguyên:

```bash
terraform apply lab.tfplan
aws eks update-kubeconfig --name eks-cluster --region us-east-1
kubectl get nodes
kubectl get pods -n kube-system
```

Phiên tạo cluster được bootstrap quyền quản trị. Node phải Ready trước bước tiếp theo. Nếu kubectl chưa có, cài theo tài liệu AWS, phiên bản phù hợp cluster 1.35.

## 3. GitHub Actions tạo image

Trong GitHub → Settings → Secrets and variables → Actions, thêm ba repository secrets lấy từ phiên Learner Lab đang chạy: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN. Cập nhật khi phiên thay đổi/hết hạn; không đưa giá trị vào Git/chat.

Actions → app-cd pipeline → Run workflow → main. Workflow dùng quyền contents:write tại job cập nhật manifest; branch protection cần cho phép cách push này. Nếu workflow bị Checkov/Trivy chặn, đọc lỗi và sửa, không bỏ scan để ép deploy.

Sau khi thành công, Git có commit đổi image tag cho 9 Deployment; ECR có image tương ứng. CloudShell cần `git pull --ff-only` trước khi đọc manifest mới.

## 4. Cài Argo CD, chưa sync root-app

```bash
kubectl create namespace argo-cd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -n argo-cd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argo-cd --timeout=300s
```

Đây là bước cài bộ điều khiển, chưa deploy application. Với repo private, cấu hình repository credential trong Argo CD trước khi đồng bộ.

## 5. Điều kiện để deploy ứng dụng gốc

Chưa chạy `kubectl apply -f kubernetes/argocd/root-app.yaml`: root và các child app tự sync, nên sẽ tạo ngay các resource chưa sẵn sàng.

- Các service account vẫn trỏ tới role riêng của tác giả đã đổi account, nhưng role chưa tồn tại. LabRole không có trust IRSA. Cần quyết định cơ chế cấp quyền được Lab hỗ trợ; không tự thay mọi annotation sang LabRole.
- PostgreSQL cần Secrets Store CSI + AWS provider + quyền đọc secret; EBS PVC cần EBS CSI + quyền AWS. Không thay PVC bằng dữ liệu tạm.
- Manifest tham chiếu application-secret-sqs nhưng repo chưa có resource tạo secret này.
- REDIS_URL mà gateway đọc cần khớp ConfigMap/env hiện tại.
- NetworkPolicy default-deny cần bổ sung egress đúng cho DNS/database/AWS; policy worker bị trùng tên và policy database sai namespace cần sửa.
- Chưa có domain: ingress/ACME/DNS placeholder không hoạt động. Dùng port-forward từ máy có kubeconfig để thử trước; chưa bật DNS/cert automation.

Sau khi các điều kiện được xử lý, từ thư mục gốc repo chạy:

```bash
kubectl apply -f kubernetes/argocd/root-app.yaml
kubectl get applications -n argo-cd
kubectl get pods -A
kubectl get pvc -A
```

Chỉ bootstrap root-app, không bootstrap thêm argocd-app.yaml. Argo lần lượt nhận infrastructure/database/application từ Git. Kiểm tra PVC Bound, Pod Ready và Argo Synced/Healthy; debug bằng describe và logs khi chưa đạt.

## Dọn tài nguyên

Dùng cùng bucket state, repo và learner-lab.tfvars cho mọi lần thao tác. Khi cần kết thúc, gỡ resource Kubernetes tạo AWS load balancer trước, rồi xem `terraform plan -destroy -var-file=learner-lab.tfvars` và chạy `terraform destroy -var-file=learner-lab.tfvars`. Terraform chỉ xóa tài nguyên nó quản lý; kiểm tra EBS/LB phát sinh từ Kubernetes riêng. Không xóa bucket state khi còn tài nguyên.
