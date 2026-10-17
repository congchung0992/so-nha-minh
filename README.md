# Sổ Nhà Mình

Sổ thu chi chung cho cả gia đình: ghi thu chi theo hạng mục có icon, nhiều ví, báo cáo tháng, nhập sao kê Techcombank, xuất Excel.

- **Giao diện:** một trang tĩnh (`index.html`), chạy trên Cloudflare Pages, không cần bước build.
- **Dữ liệu:** Supabase (dự án `so-nha-minh`, vùng Singapore). Mỗi "nhà" là một sổ; người nhà vào sổ bằng mã mời 6 ký tự.
- **Bảo mật:** mọi bảng bật Row Level Security, chỉ thành viên của nhà mới đọc/ghi được dữ liệu của nhà đó. Khoá trong `config.js` là khoá publishable, được phép công khai.

## Cấu trúc

| File | Vai trò |
|---|---|
| `index.html` | Toàn bộ app (giao diện + logic) |
| `config.js` | Địa chỉ và khoá publishable của Supabase |
| `vendor/` | supabase-js 2.45.4, SheetJS 0.18.5 (đóng gói sẵn, không phụ thuộc CDN) |
| `supabase/schema.sql` | Bảng, hàm và chính sách phân quyền |
| `_headers` | Header bảo mật và cache cho Cloudflare Pages |
| `manifest.webmanifest`, `icon*.png/svg` | Cài app ra màn hình chính điện thoại |

## Bảng dữ liệu

`households` (nhà, mã mời) · `members` (thành viên, tên hiển thị, vai trò) · `wallets` (ví) · `categories` (hạng mục, icon) · `tx` (giao dịch).

Giao dịch nhập từ sao kê có `id` cố định theo nội dung (ngày, số tiền, số tham chiếu, diễn giải), nên nhập lại sao kê trùng ngày không bị nhân đôi. Cột `src` ghi mã lần nhập để hoàn tác.

## Triển khai trên Cloudflare Pages

1. Cloudflare → Workers & Pages → Create → Pages → Connect to Git → chọn repo này.
2. Framework preset: **None**. Build command: để trống. Output directory: `/`.
3. Deploy. Lấy địa chỉ `*.pages.dev`.

## Cấu hình đăng nhập trên Supabase (làm một lần)

Supabase → Authentication → URL Configuration:
- **Site URL:** địa chỉ Cloudflare Pages của app.
- **Redirect URLs:** thêm cùng địa chỉ đó.

Không có bước này, link xác nhận email sẽ trỏ về `localhost`.
