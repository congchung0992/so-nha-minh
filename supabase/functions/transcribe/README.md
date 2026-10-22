# transcribe

Edge Function nhận file ghi âm từ app (Nói để ghi), gửi Groq Whisper (`whisper-large-v3`, tiếng Việt)
và trả về `{ text }`. Đã deploy lên Supabase project bằng MCP; mã nguồn đang chạy xem trong Supabase Dashboard
› Edge Functions › transcribe.

Khoá Groq: secret `GROQ_API_KEY`, hoặc bảng `private.app_secrets` đọc qua hàm `public.get_app_secret`
(chỉ `service_role` được gọi).
