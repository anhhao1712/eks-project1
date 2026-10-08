# Deploy theo từng bước trong CloudShell

Cấu hình hạ tầng dùng LabRole. Manifest ứng dụng đã điều chỉnh cho phiên Learner Lab; secrets được nạp bởi CloudShell thay cho IRSA/Secrets Store CSI. Chưa kiểm chứng toàn bộ ứng dụng trên AWS.

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

## 5. Secrets và deploy ứng dụng sau khi EBS đã được kiểm tra

Manifest đã bỏ Secrets Store CSI mounts và annotation IRSA chưa tồn tại. Vẫn giữ StatefulSet/PVC EBS và replica gốc. Secrets Manager vẫn lưu mật khẩu; CloudShell nạp vào Kubernetes Secret bằng script. Credentials SQS dùng phiên Lab tạm, cần cập nhật khi hết hạn.

Trên máy bạn: commit/push các sửa đổi mới, chạy lại app-cd pipeline vì dashboard có proxy cùng origin và frontend dùng URL tương đối. Chờ workflow xanh trước khi deploy.

Trong CloudShell:

```bash
cd ~/eks-deploy
git pull --ff-only
python3 scripts/load-lab-secrets.py
```

Script kiểm tra account/context, lấy queue URL, đọc eks/postgres (tạo mật khẩu ngẫu nhiên nếu secret chưa có và chưa tồn tại PVC PostgreSQL), ghi database_url vào Secrets Manager rồi tạo ba Kubernetes Secrets. Không in mật khẩu/credentials. Nếu AccessDenied, dừng; script chưa được chạy trên AWS từ máy Codex.

```bash
kubectl apply -f kubernetes/infrastructure/namespaces/
kubectl apply -f kubernetes/infrastructure/priority-class.yaml
kubectl apply -f kubernetes/argocd/root-app.yaml
kubectl get applications -n argo-cd
kubectl get pvc -n database-ns
kubectl get pods -n database-ns
kubectl get pods -n application-namespace
```

Argo tự sync; đợi vài phút và chạy lại lệnh kiểm tra. Mục tiêu PVC Bound, Pod Ready, Argo Synced/Healthy. Root app loại khỏi sync các resource cần domain/ACME, Karpenter/KEDA, snapshot controller, Secrets Store CSI và ingress chưa cài controller. NetworkPolicy đã bổ sung kết nối DNS, nội bộ và HTTPS ra AWS. Sync wave sắp xếp các child Application, startup probe cho phép service chờ DB; không bảo đảm DB Ready trước mọi app.

Khi lỗi:

```bash
kubectl get events -n application-namespace --sort-by=.lastTimestamp
kubectl get events -n database-ns --sort-by=.lastTimestamp
```

Lấy logs/describe của Pod lỗi. Không xóa PVC để thử lại vì sẽ mất dữ liệu.

### Mở dashboard trên máy Windows

CloudShell không mở được port-forward ra trình duyệt máy bạn. Cài AWS CLI v2 trên Windows từ trang AWS; kubectl đã có trên máy. Trong PowerShell tại repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\open-lab-dashboard.ps1
```

Script hỏi ba credentials phiên Lab (ẩn khi nhập), cập nhật kubeconfig và mở port-forward. Mở http://localhost:8086, giữ terminal chạy. Frontend gọi API cùng địa chỉ; dashboard chuyển /auth và /api đến gateway, không cần domain. Chỉ dùng cho học Lab; cơ chế login gốc chấp nhận thông tin tùy ý.

### Khi phiên Lab hết hạn

Trong CloudShell của phiên mới:

```bash
cd ~/eks-deploy
python3 scripts/load-lab-secrets.py
kubectl rollout restart deployment/order-service-deployment deployment/payment-service-deployment deployment/shipping-service-deployment deployment/worker-deployment -n application-namespace
```

Cập nhật ba GitHub secrets trước lần build tiếp theo. Chạy lại script mở dashboard ở máy Windows với credentials mới. Mật khẩu PostgreSQL giữ nguyên, script không tự xoay mật khẩu DB.

### EBS controller dùng credentials node

Đã kiểm chứng trên cluster: controller hostNetwork=true chạy 6/6; PVC thử Bound và ghi được EBS_OK. Giữ hop limit=1 ở launch template. Patch trực tiếp có thể bị ghi đè khi cập nhật add-on; nếu xảy ra, áp dụng lại:

```bash
kubectl patch deployment ebs-csi-controller -n kube-system --type=merge -p '{"spec":{"template":{"spec":{"hostNetwork":true,"dnsPolicy":"ClusterFirstWithHostNet"}}}}'
```

Không tạo thêm bản EBS CSI qua Helm khi đang dùng managed add-on.

## Dọn tài nguyên

Dùng cùng bucket state, repo và learner-lab.tfvars cho mọi lần thao tác. Khi cần kết thúc, gỡ resource Kubernetes tạo AWS load balancer trước, rồi xem `terraform plan -destroy -var-file=learner-lab.tfvars` và chạy `terraform destroy -var-file=learner-lab.tfvars`. Terraform chỉ xóa tài nguyên nó quản lý; kiểm tra EBS/LB phát sinh từ Kubernetes riêng. Không xóa bucket state khi còn tài nguyên.
