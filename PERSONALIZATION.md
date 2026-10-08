# Cá nhân hóa cấu hình, giữ kiến trúc tác giả

Đã pull bằng `git pull --ff-only`: repo đã up to date. Bộ cấu hình lab riêng trước đó không còn trong checkout này; lần sửa hiện tại dùng trực tiếp các tệp gốc.

## Giá trị đã đổi

| Mục | Cấu hình hiện tại |
|---|---|
| Repo Argo CD | `https://github.com/anhhao1712/eks-project1.git` |
| AWS account | `425959969184`, lấy theo pipeline/image hiện có; chưa xác minh bằng STS |
| Region | `us-east-1`, thống nhất Terraform, Helm values, KEDA và StorageClass |
| ECR | Giữ chín image/tag đã có; Terraform repository names khớp prefix `eks-project1-lab/` của workflow |
| OIDC trust trong Terraform | Lấy từ issuer của cluster thực tế, không giữ ID cluster tác giả |
| Secret ARN trong Terraform | PostgreSQL nhận ARN thật qua biến; database_url lấy ARN từ resource, không giữ suffix secret tác giả |
| Root region | Truyền xuống từng child module để đổi region một nơi không bị module dùng region khác |

Giữ 2 replica của các Deployment ứng dụng, StatefulSet PostgreSQL/Redis với PVC EBS, IRSA, Secrets Manager CSI, Traefik, TLS, KEDA và cấu trúc Argo app-of-apps. Code Go chỉ đổi CORS origin; HTML chỉ đổi URL API, chưa đổi nghiệp vụ hay cách phục vụ giao diện. Không thêm proxy, database tạm hay namespace triển khai mới.

Database và infrastructure Argo Application được thêm `directory.recurse: true` để Argo đọc các manifest trong thư mục con như application-app đã làm. Đây là sửa cách đọc cấu hình, không đổi kiến trúc.

## Các mục chưa có giá trị thật

Bạn xác nhận chưa có domain. Vì vậy tên miền được đặt thành marker `ecommerce.example.invalid`; nó không phải domain sử dụng được. Trước khi triển khai HTTPS/DNS, thay đồng bộ ở:

- `kubernetes/application/api-gateway/ingress.yaml`: `api.<domain>` và TLS hosts.
- `kubernetes/application/dashboard-api/ingress.yaml`: `dashboard.<domain>` và TLS hosts.
- `services/dashboard-api/static/index.html`: URL API.
- `services/api-gateway/main.go`: dashboard origin cho CORS.
- `terraform/helm-values/argo-cd.yaml`: `argocd.<domain>`.
- `terraform/helm-values/external-dns.yaml`: domainFilters.
- `kubernetes/infrastructure/issuer.yaml`: dnsZones, email và Hosted Zone ID.

`REPLACE_WITH_YOUR_ACME_EMAIL`, `REPLACE_WITH_YOUR_HOSTED_ZONE_ID` và `REPLACE_WITH_YOUR_TERRAFORM_STATE_BUCKET` phải được thay bằng tài nguyên/thông tin của bạn. Terraform input `route53_zone_id` phải khớp Hosted Zone trong issuer; input `postgres_secret_arn` phải là ARN thật của secret `eks/postgres`. Không đưa password hay credential AWS vào file được commit; `.tfvars` hiện được gitignore.

AZ `us-east-1a/b/c` trong StorageClass và subnet Terraform cần đối chiếu các AZ/subnet thực sự dùng trước khi tạo hạ tầng hoặc PVC.

## IAM trong Learner Lab: chưa được xác minh

Đổi account trong annotation ARN chỉ là sửa địa chỉ cấu hình. Các role giữ tên theo kiến trúc tác giả; chưa có bằng chứng các role đó tồn tại trong account lab hoặc có trust/policy đúng. Không thay toàn bộ bằng `LabRole`.

Cần kiểm tra:

1. Role cluster và node có sẵn, trust đúng, lab cho phép `iam:PassRole` và tạo EKS/node group.
2. OIDC provider của cluster và role IRSA tin đúng namespace/ServiceAccount.
3. Role cho Pod đọc secret có `secretsmanager:GetSecretValue`/`DescribeSecret`; publisher và worker có các quyền SQS tương ứng. Role có quyền secret không mặc nhiên có quyền SQS.
4. EBS CSI controller có role/trust/quyền tạo và gắn volume.
5. KEDA, ExternalDNS, cert-manager, load balancer controller và Karpenter có quyền phù hợp nếu triển khai.

Terraform gốc vẫn tạo IAM role, policy và OIDC provider. **Không chạy terraform apply trong lab không cho chỉnh IAM** chỉ vì đã cá nhân hóa xong. Giữ Terraform để học kiến trúc; phải xác minh quyền và cách dùng tài nguyên có sẵn trước khi chọn quy trình provision.

## Các phụ thuộc gốc cần xử lý trước khi Sync

- Deployment tham chiếu `application-secret-sqs` nhưng repo chưa định nghĩa cách tạo nó. Secret cần chứa SQS_QUEUE_URL và AWS_REGION đúng account/region; nếu muốn giữ CSI, bổ sung secret nguồn và mapping CSI phù hợp sau khi xác minh role đọc secret.
- Gateway đọc REDIS_URL trong khi redis-config hiện khai báo REDIS_HOST/REDIS_PORT; cần đối chiếu cấu hình khi kiểm tra app.
- NetworkPolicy gốc có default-deny egress thiếu allow rules và nhiều worker policy trùng tên. Đây là vấn đề kết nối riêng, không được chữa bằng thay region.
- Có hai cách bootstrap Argo (`root-app.yaml` và `argocd-app.yaml`). Dùng root-app cho app-of-apps theo cấu trúc repo; không áp dụng cả hai rồi để chúng tranh quản lý cùng tài nguyên.
- Chưa có EKS theo xác nhận trước của bạn. Các workflow infrastructure/destroy hiện chỉ kiểm tra hoặc cố ý dừng, không tạo/xóa cluster.

Các điểm này được ghi lại để không nhầm “đã đổi thông tin cá nhân” với “đã sẵn sàng deploy”. Lần sửa này chưa thay thiết kế authentication, storage, replica hoặc networking của tác giả.

## Kiểm tra và bước tiếp theo

Đọc `git diff` để thấy thay đổi từng dòng. YAML được kiểm tra parse; có kiểm tra giữ nguyên replicas, PVC/CSI và image tag. Chưa chạy Go/Docker build, Terraform validate hoặc xác minh quyền AWS trên tài khoản thật.

Chỉ commit/push sau khi bạn review và điền các mục còn thiếu. Chưa có tài nguyên AWS nào được tạo bởi việc sửa những file này.
