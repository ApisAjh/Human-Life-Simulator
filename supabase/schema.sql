-- Human Life Simulator: schema + RLS + fungsi game atomik
create table if not exists items (
  id text primary key, name text not null, kind text not null default 'food',
  icon text not null, price int not null check (price >= 0),
  hunger int not null default 0, happy int not null default 0, health int not null default 0
);
create table if not exists jobs (
  id text primary key, name text not null, level_req int not null default 1,
  cooldown_sec int not null, pay int not null, xp int not null, energy_cost int not null
);
create table if not exists characters (
  user_id uuid primary key references auth.users on delete cascade,
  name text not null default 'Aku' check (char_length(name) between 1 and 20),
  skin text not null default '#f1c27d', hair text not null default '#3b2a20', shirt text not null default '#5fa8d3',
  level int not null default 1, xp int not null default 0,
  money int not null default 100 check (money >= 0),
  hunger int not null default 80 check (hunger between 0 and 100),
  energy int not null default 80 check (energy between 0 and 100),
  clean  int not null default 80 check (clean  between 0 and 100),
  happy  int not null default 80 check (happy  between 0 and 100),
  health int not null default 90 check (health between 0 and 100),
  social int not null default 60 check (social between 0 and 100),
  sleep_start timestamptz, work_ready_at timestamptz not null default now(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists inventory (
  user_id uuid references auth.users on delete cascade,
  item_id text references items(id), qty int not null default 0 check (qty >= 0),
  primary key (user_id, item_id)
);
create table if not exists transactions (
  id bigserial primary key, user_id uuid not null references auth.users on delete cascade,
  kind text not null, amount int not null, ref text, created_at timestamptz not null default now()
);
create index if not exists tx_user_idx on transactions (user_id, created_at desc);

alter table items enable row level security;
alter table jobs enable row level security;
alter table characters enable row level security;
alter table inventory enable row level security;
alter table transactions enable row level security;
create policy "items publik" on items for select using (true);
create policy "jobs publik" on jobs for select using (true);
create policy "karakter milik sendiri" on characters for select using (auth.uid() = user_id);
create policy "inventaris milik sendiri" on inventory for select using (auth.uid() = user_id);
create policy "transaksi milik sendiri" on transactions for select using (auth.uid() = user_id);
-- Tidak ada policy insert/update/delete: semua perubahan hanya lewat game_action (service role).

create or replace function game_action(p_user uuid, p_action text, p_arg text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c characters%rowtype; it items%rowtype; j jobs%rowtype; h numeric;
begin
  insert into characters(user_id) values (p_user) on conflict do nothing;
  select * into c from characters where user_id = p_user for update;  -- kunci baris: anti request ganda

  if c.sleep_start is null then  -- penurunan kebutuhan berbasis waktu server (maks 12 jam, tidak turun di bawah 5)
    h := least(extract(epoch from now() - c.updated_at) / 3600.0, 12);
    c.hunger := least(c.hunger, greatest(5, c.hunger - round(h*5)::int));
    c.energy := least(c.energy, greatest(5, c.energy - round(h*3)::int));
    c.clean  := least(c.clean,  greatest(5, c.clean  - round(h*3)::int));
    c.happy  := least(c.happy,  greatest(5, c.happy  - round(h*4)::int));
    c.social := least(c.social, greatest(5, c.social - round(h*2)::int));
    if c.hunger < 15 or c.clean < 15 then
      c.health := least(c.health, greatest(10, c.health - round(h*3)::int));
    else c.health := least(100, c.health + round(h)::int); end if;
  end if;
  c.updated_at := now();

  if c.sleep_start is not null and p_action not in ('state','wake','style') then
    raise exception 'Karakter sedang tidur';
  end if;

  if p_action = 'state' then null;
  elsif p_action = 'buy' then
    select * into it from items where id = p_arg;
    if not found then raise exception 'Item tidak ada'; end if;
    if c.money < it.price then raise exception 'Uang tidak cukup'; end if;
    c.money := c.money - it.price;
    insert into inventory(user_id,item_id,qty) values (p_user,it.id,1)
      on conflict (user_id,item_id) do update set qty = inventory.qty + 1;
    insert into transactions(user_id,kind,amount,ref) values (p_user,'buy',-it.price,it.id);
  elsif p_action = 'eat' then
    select * into it from items where id = p_arg and kind = 'food';
    if not found then raise exception 'Makanan tidak ada'; end if;
    update inventory set qty = qty - 1 where user_id = p_user and item_id = it.id and qty > 0;
    if not found then raise exception 'Item habis'; end if;
    c.hunger := least(100, c.hunger + it.hunger); c.happy := least(100, c.happy + it.happy);
    c.health := least(100, c.health + it.health); c.xp := c.xp + 2;
  elsif p_action = 'bathe' then
    c.clean := least(100, c.clean + 40); c.happy := least(100, c.happy + 3); c.xp := c.xp + 2;
  elsif p_action = 'play' then
    if c.energy < 10 then raise exception 'Energi kurang'; end if;
    c.happy := least(100, c.happy + 20); c.energy := c.energy - 10;
    c.hunger := greatest(5, c.hunger - 5); c.xp := c.xp + 3;
  elsif p_action = 'social' then
    if c.energy < 5 then raise exception 'Energi kurang'; end if;
    c.social := least(100, c.social + 25); c.happy := least(100, c.happy + 5);
    c.energy := c.energy - 5; c.xp := c.xp + 3;
  elsif p_action = 'sleep' then
    c.sleep_start := now();
  elsif p_action = 'wake' then
    if c.sleep_start is null then raise exception 'Tidak sedang tidur'; end if;
    h := least(extract(epoch from now() - c.sleep_start) / 3600.0, 8);
    c.energy := least(100, c.energy + round(h*15)::int);
    c.hunger := greatest(5, c.hunger - round(h*2)::int);
    c.sleep_start := null;
  elsif p_action = 'work' then
    select * into j from jobs where id = p_arg;
    if not found then raise exception 'Pekerjaan tidak ada'; end if;
    if c.level < j.level_req then raise exception 'Level belum cukup'; end if;
    if now() < c.work_ready_at then raise exception 'Masih cooldown'; end if;
    if c.energy < j.energy_cost then raise exception 'Energi kurang'; end if;
    c.energy := c.energy - j.energy_cost; c.money := c.money + j.pay; c.xp := c.xp + j.xp;
    c.hunger := greatest(5, c.hunger - 5);
    c.work_ready_at := now() + make_interval(secs => j.cooldown_sec);
    insert into transactions(user_id,kind,amount,ref) values (p_user,'work',j.pay,j.id);
  elsif p_action = 'style' then
    if p_arg !~ '^(skin|hair|shirt):#[0-9a-fA-F]{6}$' then raise exception 'Gaya tidak valid'; end if;
    if split_part(p_arg,':',1) = 'skin' then c.skin := split_part(p_arg,':',2);
    elsif split_part(p_arg,':',1) = 'hair' then c.hair := split_part(p_arg,':',2);
    else c.shirt := split_part(p_arg,':',2); end if;
  else raise exception 'Aksi tidak dikenal';
  end if;

  c.level := 1 + c.xp / 100;
  update characters set skin=c.skin, hair=c.hair, shirt=c.shirt, level=c.level, xp=c.xp, money=c.money,
    hunger=c.hunger, energy=c.energy, clean=c.clean, happy=c.happy, health=c.health, social=c.social,
    sleep_start=c.sleep_start, work_ready_at=c.work_ready_at, updated_at=c.updated_at
  where user_id = p_user;

  return jsonb_build_object('character', to_jsonb(c),
    'inventory', (select coalesce(jsonb_object_agg(item_id, qty), '{}'::jsonb) from inventory where user_id = p_user and qty > 0));
end $$;
revoke all on function game_action(uuid,text,text) from public, anon, authenticated;
grant execute on function game_action(uuid,text,text) to service_role;

insert into items(id,name,kind,icon,price,hunger,happy,health) values
 ('roti','Roti','food','🍞',10,15,0,0),('nasi','Nasi & Lauk','food','🍛',25,35,3,0),
 ('mie','Mi','food','🍜',20,30,2,0),('apel','Buah Apel','food','🍎',8,10,0,3),
 ('susu','Susu','food','🥛',15,12,0,5),('air','Air Minum','food','💧',5,3,0,2),
 ('kue','Makanan Spesial','food','🎂',60,40,15,0) on conflict do nothing;
insert into jobs(id,name,level_req,cooldown_sec,pay,xp,energy_cost) values
 ('barista','Barista',1,60,25,10,15),('kasir','Kasir',1,90,35,12,18),
 ('kantor','Pegawai Kantor',2,180,80,20,25),('desainer','Desainer',3,240,130,28,28),
 ('programmer','Programmer',4,300,200,40,30) on conflict do nothing;
