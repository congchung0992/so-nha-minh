-- Sổ Nhà Mình — cấu trúc dữ liệu trên Supabase
-- Mỗi "nhà" (household) là một sổ chung; thành viên vào sổ bằng mã mời.
-- Mọi bảng đều bật Row Level Security: chỉ thành viên của nhà mới đọc/ghi được dữ liệu của nhà đó.

create table if not exists public.households (
  id          text primary key default gen_random_uuid()::text,
  name        text not null default 'Nhà mình',
  join_code   text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table if not exists public.members (
  household_id text not null references public.households(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '',
  role         text not null default 'member' check (role in ('owner','member')),
  joined_at    timestamptz not null default now(),
  primary key (household_id, user_id)
);
create index if not exists members_user_idx on public.members(user_id);

create table if not exists public.wallets (
  id           text primary key default gen_random_uuid()::text,
  household_id text not null references public.households(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 60),
  type         text not null default 'cash',
  icon         text,
  initial      numeric(18,0) not null default 0,
  sort         int not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists wallets_household_idx on public.wallets(household_id);

create table if not exists public.categories (
  id           text primary key default gen_random_uuid()::text,
  household_id text not null references public.households(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 60),
  kind         text not null check (kind in ('expense','income')),
  icon         text,
  sort         int not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists categories_household_idx on public.categories(household_id);
-- hạng mục con (VD "Đi chợ/siêu thị") ghi tên hạng mục cha ("Ăn uống"); trống = hạng mục cha
alter table public.categories add column if not exists parent text not null default '';

create table if not exists public.tx (
  id            text primary key default gen_random_uuid()::text,
  household_id  text not null references public.households(id) on delete cascade,
  kind          text not null check (kind in ('expense','income','transfer')),
  amount        numeric(18,0) not null check (amount > 0),
  wallet_id     text not null references public.wallets(id) on delete restrict,
  to_wallet_id  text references public.wallets(id) on delete restrict,
  category_id   text references public.categories(id) on delete set null,
  date          date not null,
  note          text not null default '',
  ref           text not null default '',
  src           text,
  created_by    uuid default auth.uid() references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_by    uuid references auth.users(id) on delete set null,
  updated_at    timestamptz,
  constraint transfer_needs_target check (kind <> 'transfer' or (to_wallet_id is not null and to_wallet_id <> wallet_id))
);
create index if not exists tx_household_date_idx on public.tx(household_id, date desc);
create index if not exists tx_src_idx on public.tx(src) where src is not null;
create index if not exists tx_wallet_idx on public.tx(wallet_id);
create index if not exists tx_to_wallet_idx on public.tx(to_wallet_id);
create index if not exists tx_category_idx on public.tx(category_id);
create index if not exists households_created_by_idx on public.households(created_by);

-- Hàm kiểm tra thành viên (security definer để dùng trong policy mà không đệ quy)
create or replace function public.is_member(h text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members m where m.household_id = h and m.user_id = (select auth.uid()));
$$;

-- Tạo nhà mới: người tạo là chủ sổ
create or replace function public.create_household(p_name text, p_display_name text)
returns public.households language plpgsql security definer set search_path = public as $$
declare h public.households;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into public.households(name, created_by) values (coalesce(nullif(trim(p_name),''),'Nhà mình'), auth.uid()) returning * into h;
  insert into public.members(household_id, user_id, display_name, role) values (h.id, auth.uid(), coalesce(trim(p_display_name),''), 'owner');
  return h;
end $$;

-- Vào nhà bằng mã mời
create or replace function public.join_household(p_code text, p_display_name text)
returns public.households language plpgsql security definer set search_path = public as $$
declare h public.households;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into h from public.households where join_code = upper(trim(p_code));
  if not found then raise exception 'invalid_code'; end if;
  insert into public.members(household_id, user_id, display_name) values (h.id, auth.uid(), coalesce(trim(p_display_name),''))
    on conflict (household_id, user_id) do update set display_name = excluded.display_name;
  return h;
end $$;

-- Chủ sổ đổi mã mời (khi lỡ chia sẻ nhầm)
create or replace function public.rotate_join_code(p_household text)
returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not exists (select 1 from public.members where household_id = p_household and user_id = auth.uid() and role = 'owner') then
    raise exception 'not_owner'; end if;
  c := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  update public.households set join_code = c where id = p_household;
  return c;
end $$;

revoke all on function public.create_household(text,text) from public, anon;
revoke all on function public.join_household(text,text) from public, anon;
revoke all on function public.rotate_join_code(text) from public, anon;
grant execute on function public.create_household(text,text) to authenticated;
grant execute on function public.join_household(text,text) to authenticated;
grant execute on function public.rotate_join_code(text) to authenticated;
revoke all on function public.is_member(text) from public, anon;
grant execute on function public.is_member(text) to authenticated;

alter table public.households enable row level security;
alter table public.members    enable row level security;
alter table public.wallets    enable row level security;
alter table public.categories enable row level security;
alter table public.tx         enable row level security;

drop policy if exists households_read   on public.households;
drop policy if exists households_update on public.households;
create policy households_read   on public.households for select to authenticated using (public.is_member(id));
create policy households_update on public.households for update to authenticated using (public.is_member(id)) with check (public.is_member(id));

drop policy if exists members_read        on public.members;
drop policy if exists members_update_self on public.members;
drop policy if exists members_leave       on public.members;
create policy members_read        on public.members for select to authenticated using (public.is_member(household_id));
create policy members_update_self on public.members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy members_leave       on public.members for delete to authenticated using (user_id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['wallets','categories','tx'] loop
    execute format('drop policy if exists %1$s_all on public.%1$s', t);
    execute format('create policy %1$s_all on public.%1$s for all to authenticated using (public.is_member(household_id)) with check (public.is_member(household_id))', t);
  end loop;
end $$;

-- Cập nhật trực tiếp giữa các máy (Realtime)
alter table public.tx replica identity full;
alter table public.wallets replica identity full;
alter table public.categories replica identity full;
do $$
begin
  begin alter publication supabase_realtime add table public.wallets;    exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.categories; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.tx;         exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.members;    exception when duplicate_object then null; end;
end $$;

-- Gộp ví p_src vào ví p_dst: chuyển mọi giao dịch sang p_dst, bỏ các lần chuyển qua lại giữa hai ví (thành chuyển cho chính mình),
-- cộng số dư ban đầu, rồi xoá ví p_src. Chạy trọn trong một giao dịch.
create or replace function public.merge_wallets(p_household text, p_src text, p_dst text)
returns integer language plpgsql security invoker set search_path = public as $$
declare moved integer;
begin
  if p_src = p_dst then raise exception 'same_wallet'; end if;
  -- chạy với quyền người gọi: RLS chỉ cho thấy ví của nhà mình, nên người ngoài sẽ rơi vào wallet_not_found
  if not exists (select 1 from wallets where id = p_src and household_id = p_household)
     or not exists (select 1 from wallets where id = p_dst and household_id = p_household) then
    raise exception 'wallet_not_found';
  end if;
  delete from tx where household_id = p_household and kind = 'transfer'
    and ((wallet_id = p_src and to_wallet_id = p_dst) or (wallet_id = p_dst and to_wallet_id = p_src));
  update tx set wallet_id = p_dst where household_id = p_household and wallet_id = p_src;
  get diagnostics moved = row_count;
  update tx set to_wallet_id = p_dst where household_id = p_household and to_wallet_id = p_src;
  update wallets set initial = initial + (select initial from wallets where id = p_src) where id = p_dst;
  delete from wallets where id = p_src;
  return moved;
end $$;
revoke all on function public.merge_wallets(text,text,text) from public, anon;
grant execute on function public.merge_wallets(text,text,text) to authenticated;
