-- v3: character_stats terpisah, pekerjaan berdurasi, gaya rambut/mata, misi "jaga kebutuhan".
-- Jalankan SETELAH schema.sql dan v2.sql. Aman diulang.
create table if not exists character_stats (
  user_id uuid primary key references characters(user_id) on delete cascade,
  hunger int not null default 80 check (hunger between 0 and 100), energy int not null default 80 check (energy between 0 and 100),
  clean int not null default 80 check (clean between 0 and 100), happy int not null default 80 check (happy between 0 and 100),
  health int not null default 90 check (health between 0 and 100), social int not null default 60 check (social between 0 and 100),
  sleep_start timestamptz, work_ready_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table character_stats enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'character_stats') then
    create policy "stats sendiri" on character_stats for select using (auth.uid() = user_id);
  end if;
  if exists (select 1 from information_schema.columns where table_name = 'characters' and column_name = 'hunger') then
    insert into character_stats(user_id,hunger,energy,clean,happy,health,social,sleep_start,work_ready_at,updated_at)
      select user_id,hunger,energy,clean,happy,health,social,sleep_start,work_ready_at,updated_at from characters on conflict do nothing;
    alter table characters drop column hunger, drop column energy, drop column clean, drop column happy,
      drop column health, drop column social, drop column sleep_start, drop column work_ready_at, drop column updated_at;
  end if;
end $$;
alter table characters add column if not exists hair_style int not null default 0 check (hair_style between 0 and 3),
  add column if not exists eye_style int not null default 0 check (eye_style between 0 and 3),
  add column if not exists work_job text, add column if not exists work_end timestamptz;
alter table jobs add column if not exists duration_sec int not null default 60;
update jobs set duration_sec = case id when 'barista' then 30 when 'kasir' then 45 when 'kantor' then 60 when 'desainer' then 90 else 120 end;
insert into missions values ('d_care','Jaga semua kebutuhan ≥ 50 (5 aksi)','daily','care',5,40,12) on conflict do nothing;

drop type if exists char_full cascade;
create type char_full as (user_id uuid, name text, skin text, hair text, shirt text, accessory text, hair_style int, eye_style int,
  level int, xp int, money int, last_daily date, code text, work_job text, work_end timestamptz, created_at timestamptz,
  hunger int, energy int, clean int, happy int, health int, social int, sleep_start timestamptz, work_ready_at timestamptz, updated_at timestamptz);

create or replace function game_action(p_user uuid, p_action text, p_arg text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c char_full; it items%rowtype; j jobs%rowtype; m missions%rowtype; a achievements%rowtype; h numeric; n int; f uuid; v jsonb;
begin
  insert into characters(user_id) values (p_user) on conflict do nothing;
  insert into character_stats(user_id) values (p_user) on conflict do nothing;
  select ch.user_id, ch.name, ch.skin, ch.hair, ch.shirt, ch.accessory, ch.hair_style, ch.eye_style, ch.level, ch.xp, ch.money,
    ch.last_daily, ch.code, ch.work_job, ch.work_end, ch.created_at, st.hunger, st.energy, st.clean, st.happy, st.health, st.social,
    st.sleep_start, st.work_ready_at, st.updated_at
  into c from characters ch join character_stats st on st.user_id = ch.user_id where ch.user_id = p_user for update of ch, st;

  if c.sleep_start is null then
    h := least(extract(epoch from now() - c.updated_at) / 3600.0, 12);
    c.hunger := least(c.hunger, greatest(5, c.hunger - round(h*5)::int));
    c.energy := least(c.energy, greatest(5, c.energy - round(h*3)::int));
    c.clean  := least(c.clean,  greatest(5, c.clean  - round(h*3)::int));
    c.happy  := least(c.happy,  greatest(5, c.happy  - round(h*4)::int));
    c.social := least(c.social, greatest(5, c.social - round(h*2)::int));
    if c.hunger < 15 or c.clean < 15 then c.health := least(c.health, greatest(10, c.health - round(h*3)::int));
    else c.health := least(100, c.health + round(h)::int); end if;
  elsif p_action in ('state','missions','friends') then
    -- Proses tidur diselesaikan bertahap ketika aplikasi meminta state.
    -- Timestamp digeser agar progres yang sama tidak dihitung dua kali.
    h := least(extract(epoch from now() - c.sleep_start) / 3600.0, 8);
    c.energy := least(100, c.energy + round(h*15)::int);
    c.hunger := greatest(5, c.hunger - round(h*2)::int);
    c.sleep_start := now();
  end if;
  c.updated_at := now();

  if c.sleep_start is not null and p_action in ('eat','bathe','play','social','sleep','work','work_done') then raise exception 'Karakter sedang tidur'; end if;
  if c.work_job is not null and p_action in ('sleep','bathe','play','social') then raise exception 'Sedang bekerja'; end if;

  if p_action in ('state','missions','friends') then null;
  elsif p_action = 'buy' then
    select * into it from items where id = p_arg;
    if not found then raise exception 'Item tidak ada'; end if;
    if c.money < it.price then raise exception 'Uang tidak cukup'; end if;
    c.money := c.money - it.price;
    insert into inventory(user_id,item_id,qty) values (p_user,it.id,1) on conflict (user_id,item_id) do update set qty = inventory.qty + 1;
    insert into transactions(user_id,kind,amount,ref) values (p_user,'buy',-it.price,it.id);
  elsif p_action = 'eat' then
    select * into it from items where id = p_arg and kind = 'food';
    if not found then raise exception 'Makanan tidak ada'; end if;
    update inventory set qty = qty - 1 where user_id = p_user and item_id = it.id and qty > 0;
    if not found then raise exception 'Item habis'; end if;
    c.hunger := least(100, c.hunger + it.hunger); c.happy := least(100, c.happy + it.happy);
    c.health := least(100, c.health + it.health); c.xp := c.xp + 2; perform bump(p_user,'eat');
  elsif p_action = 'bathe' then
    c.clean := least(100, c.clean + 40); c.happy := least(100, c.happy + 3); c.xp := c.xp + 2; perform bump(p_user,'bathe');
  elsif p_action = 'play' then
    if c.energy < 10 then raise exception 'Energi kurang'; end if;
    c.happy := least(100, c.happy + 20); c.energy := c.energy - 10; c.hunger := greatest(5, c.hunger - 5);
    c.xp := c.xp + 3; perform bump(p_user,'play');
  elsif p_action = 'social' then
    if c.energy < 5 then raise exception 'Energi kurang'; end if;
    c.social := least(100, c.social + 25); c.happy := least(100, c.happy + 5); c.energy := c.energy - 5;
    c.xp := c.xp + 3; perform bump(p_user,'social');
  elsif p_action = 'sleep' then c.sleep_start := now();
  elsif p_action = 'wake' then
    if c.sleep_start is null then raise exception 'Tidak sedang tidur'; end if;
    h := least(extract(epoch from now() - c.sleep_start) / 3600.0, 8);
    c.energy := least(100, c.energy + round(h*15)::int); c.hunger := greatest(5, c.hunger - round(h*2)::int); c.sleep_start := null;
  elsif p_action = 'work' then
    if c.work_job is not null then raise exception 'Sedang bekerja'; end if;
    select * into j from jobs where id = p_arg;
    if not found then raise exception 'Pekerjaan tidak ada'; end if;
    if c.level < j.level_req then raise exception 'Level belum cukup'; end if;
    if now() < c.work_ready_at then raise exception 'Masih cooldown'; end if;
    if c.energy < j.energy_cost then raise exception 'Energi kurang'; end if;
    c.energy := c.energy - j.energy_cost; c.work_job := j.id; c.work_end := now() + make_interval(secs => j.duration_sec);
  elsif p_action = 'work_done' then
    if c.work_job is null then raise exception 'Tidak sedang bekerja'; end if;
    if now() < c.work_end then raise exception 'Pekerjaan belum selesai'; end if;
    select * into j from jobs where id = c.work_job;
    c.money := c.money + j.pay; c.xp := c.xp + j.xp; c.hunger := greatest(5, c.hunger - 5);
    c.work_ready_at := now() + make_interval(secs => j.cooldown_sec); c.work_job := null; c.work_end := null;
    insert into transactions(user_id,kind,amount,ref) values (p_user,'work',j.pay,j.id); perform bump(p_user,'work');
  elsif p_action = 'style' then
    if p_arg ~ '^(skin|hair|shirt):#[0-9a-fA-F]{6}$' then
      if split_part(p_arg,':',1) = 'skin' then c.skin := split_part(p_arg,':',2);
      elsif split_part(p_arg,':',1) = 'hair' then c.hair := split_part(p_arg,':',2);
      else c.shirt := split_part(p_arg,':',2); end if;
    elsif p_arg ~ '^(hair_style|eye_style):[0-3]$' then
      if split_part(p_arg,':',1) = 'hair_style' then c.hair_style := split_part(p_arg,':',2)::int;
      else c.eye_style := split_part(p_arg,':',2)::int; end if;
    else raise exception 'Gaya tidak valid'; end if;
  elsif p_action = 'rename' then
    if char_length(trim(coalesce(p_arg,''))) not between 1 and 20 then raise exception 'Nama 1-20 karakter'; end if;
    c.name := trim(p_arg);
  elsif p_action = 'equip' then
    if p_arg = 'none' then c.accessory := null;
    else
      select * into it from items where id = p_arg and kind = 'clothing';
      if not found then raise exception 'Pakaian tidak ada'; end if;
      if not exists (select 1 from inventory where user_id = p_user and item_id = it.id and qty > 0) then raise exception 'Belum dimiliki'; end if;
      if it.slot = 'shirt' then c.shirt := it.value; else c.accessory := it.value; end if;
    end if;
  elsif p_action = 'place' then
    select * into it from items where id = p_arg and kind = 'furniture';
    if not found then raise exception 'Furnitur tidak ada'; end if;
    delete from room_items where user_id = p_user and item_id = it.id;
    if not found then
      if not exists (select 1 from inventory where user_id = p_user and item_id = it.id and qty > 0) then raise exception 'Belum dimiliki'; end if;
      insert into room_items values (p_user, it.id);
    end if;
  elsif p_action = 'daily' then
    if c.last_daily = current_date then raise exception 'Hadiah hari ini sudah diambil'; end if;
    c.last_daily := current_date; c.money := c.money + 50; c.xp := c.xp + 5;
    insert into transactions(user_id,kind,amount,ref) values (p_user,'daily',50,null);
  elsif p_action = 'claim' then
    select * into m from missions where id = p_arg;
    if not found then raise exception 'Misi tidak ada'; end if;
    update user_missions set claimed = true where user_id = p_user and mission_id = m.id and claimed = false and progress >= m.target
      and period = case when m.kind='daily' then current_date else date_trunc('week',now())::date end;
    if not found then raise exception 'Belum bisa diklaim'; end if;
    c.money := c.money + m.reward_money; c.xp := c.xp + m.reward_xp;
    insert into transactions(user_id,kind,amount,ref) values (p_user,'mission',m.reward_money,m.id);
  elsif p_action = 'claim_ach' then
    select * into a from achievements where id = p_arg;
    if not found then raise exception 'Achievement tidak ada'; end if;
    if coalesce((select uc.n from user_counters uc where uc.user_id = p_user and uc.metric = a.metric),0) < a.target then raise exception 'Belum tercapai'; end if;
    insert into user_achievements(user_id,achievement_id) values (p_user,a.id) on conflict do nothing;
    get diagnostics n = row_count;
    if n = 0 then raise exception 'Sudah diklaim'; end if;
    c.money := c.money + a.reward_money;
    insert into transactions(user_id,kind,amount,ref) values (p_user,'achievement',a.reward_money,a.id);
  elsif p_action = 'friend_add' then
    select user_id into f from characters where code = lower(trim(coalesce(p_arg,'')));
    if f is null or f = p_user then raise exception 'Kode tidak valid'; end if;
    insert into friends values (p_user,f),(f,p_user) on conflict do nothing;
  elsif p_action = 'gift' then
    select c2.user_id into f from characters c2 join friends fr on fr.friend_id = c2.user_id and fr.user_id = p_user where c2.code = split_part(p_arg,':',1);
    if f is null then raise exception 'Teman tidak ditemukan'; end if;
    update inventory set qty = qty - 1 where user_id = p_user and item_id = split_part(p_arg,':',2) and qty > 0;
    if not found then raise exception 'Item habis'; end if;
    insert into inventory(user_id,item_id,qty) values (f, split_part(p_arg,':',2), 1) on conflict (user_id,item_id) do update set qty = inventory.qty + 1;
    delete from room_items where user_id = p_user and item_id = split_part(p_arg,':',2)
      and not exists (select 1 from inventory where user_id = p_user and item_id = split_part(p_arg,':',2) and qty > 0);
  else raise exception 'Aksi tidak dikenal';
  end if;

  if p_action in ('eat','bathe','play','social','wake','work_done')
     and least(c.hunger,c.energy,c.clean,c.happy,c.health,c.social) >= 50 then perform bump(p_user,'care'); end if;

  c.level := 1 + c.xp / 100;
  update characters set name=c.name, skin=c.skin, hair=c.hair, shirt=c.shirt, accessory=c.accessory, hair_style=c.hair_style,
    eye_style=c.eye_style, level=c.level, xp=c.xp, money=c.money, last_daily=c.last_daily, work_job=c.work_job, work_end=c.work_end
  where user_id = p_user;
  update character_stats set hunger=c.hunger, energy=c.energy, clean=c.clean, happy=c.happy, health=c.health, social=c.social,
    sleep_start=c.sleep_start, work_ready_at=c.work_ready_at, updated_at=c.updated_at where user_id = p_user;

  v := case when p_action in ('missions','claim','claim_ach') then missions_json(p_user)
            when p_action in ('friends','friend_add','gift') then friends_json(p_user) end;
  return jsonb_build_object('character', to_jsonb(c), 'data', v,
    'room', (select coalesce(jsonb_agg(item_id), '[]'::jsonb) from room_items where user_id = p_user),
    'inventory', (select coalesce(jsonb_object_agg(item_id, qty), '{}'::jsonb) from inventory where user_id = p_user and qty > 0));
end $$;
revoke all on function game_action(uuid,text,text) from public, anon, authenticated;
grant execute on function game_action(uuid,text,text) to service_role;
