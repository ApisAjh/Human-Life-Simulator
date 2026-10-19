-- v2: pakaian, furnitur, kamar, misi, achievement, hadiah harian, sosial. Jalankan SETELAH schema.sql.
alter table items add column if not exists slot text, add column if not exists value text;
alter table characters add column if not exists accessory text, add column if not exists last_daily date,
  add column if not exists code text unique default substr(md5(random()::text), 1, 8);

create table if not exists room_items (user_id uuid references auth.users on delete cascade, item_id text references items(id), primary key (user_id, item_id));
create table if not exists missions (id text primary key, title text not null, kind text not null check (kind in ('daily','weekly')),
  metric text not null, target int not null, reward_money int not null, reward_xp int not null);
create table if not exists user_missions (user_id uuid references auth.users on delete cascade, mission_id text references missions(id),
  period date not null, progress int not null default 0, claimed boolean not null default false, primary key (user_id, mission_id, period));
create table if not exists achievements (id text primary key, title text not null, metric text not null, target int not null, reward_money int not null);
create table if not exists user_achievements (user_id uuid references auth.users on delete cascade, achievement_id text references achievements(id),
  claimed_at timestamptz default now(), primary key (user_id, achievement_id));
create table if not exists user_counters (user_id uuid references auth.users on delete cascade, metric text, n int not null default 0, primary key (user_id, metric));
create table if not exists friends (user_id uuid references auth.users on delete cascade, friend_id uuid references auth.users on delete cascade, primary key (user_id, friend_id));

alter table room_items enable row level security; alter table missions enable row level security;
alter table user_missions enable row level security; alter table achievements enable row level security;
alter table user_achievements enable row level security; alter table user_counters enable row level security;
alter table friends enable row level security;
create policy "missions publik" on missions for select using (true);
create policy "achievements publik" on achievements for select using (true);
create policy "room sendiri" on room_items for select using (auth.uid() = user_id);
create policy "user_missions sendiri" on user_missions for select using (auth.uid() = user_id);
create policy "user_achievements sendiri" on user_achievements for select using (auth.uid() = user_id);
create policy "counters sendiri" on user_counters for select using (auth.uid() = user_id);
create policy "friends sendiri" on friends for select using (auth.uid() = user_id);

insert into items(id,name,kind,icon,price,slot,value) values
 ('kaos_merah','Kaos Merah','clothing','👕',40,'shirt','#e5534b'),('kaos_hijau','Kaos Hijau','clothing','👕',40,'shirt','#5fbf86'),
 ('kaos_kuning','Kaos Kuning','clothing','👕',40,'shirt','#f4c542'),('topi','Topi','clothing','🧢',50,'acc','🧢'),
 ('kacamata','Kacamata','clothing','🕶️',60,'acc','🕶️'),('mahkota','Mahkota','clothing','👑',200,'acc','👑'),
 ('kasur','Tempat Tidur','furniture','🛏️',120,null,null),('buku','Meja Belajar','furniture','📚',80,null,null),
 ('lemari','Lemari','furniture','🚪',100,null,null),('kursi','Kursi','furniture','🪑',50,null,null),
 ('tanaman','Tanaman','furniture','🪴',30,null,null),('poster','Poster','furniture','🖼️',40,null,null),
 ('lampu','Lampu','furniture','💡',35,null,null) on conflict do nothing;
insert into missions values
 ('d_eat','Makan 3 kali','daily','eat',3,30,10),('d_bathe','Mandi 1 kali','daily','bathe',1,15,5),
 ('d_work','Selesaikan 1 pekerjaan','daily','work',1,30,10),('d_play','Bermain 3 kali','daily','play',3,25,8),
 ('w_work','Bekerja 10 kali','weekly','work',10,200,50),('w_social','Bersosialisasi 5 kali','weekly','social',5,100,30) on conflict do nothing;
insert into achievements values
 ('a_work1','Kerja pertama','work',1,50),('a_work25','Pekerja keras (25x)','work',25,500),
 ('a_eat20','Tukang makan (20x)','eat',20,150),('a_social10','Mudah bergaul (10x)','social',10,150) on conflict do nothing;

create or replace function bump(p_user uuid, p_metric text) returns void language plpgsql as $$
begin
  insert into user_counters(user_id,metric,n) values (p_user,p_metric,1)
    on conflict (user_id,metric) do update set n = user_counters.n + 1;
  insert into user_missions(user_id,mission_id,period,progress)
    select p_user, m.id, case when m.kind='daily' then current_date else date_trunc('week',now())::date end, 1
    from missions m where m.metric = p_metric
  on conflict (user_id,mission_id,period) do update set progress = user_missions.progress + 1 where user_missions.claimed = false;
end $$;

create or replace function missions_json(u uuid) returns jsonb language sql stable as $$
select jsonb_build_object(
 'missions', (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'title',m.title,'kind',m.kind,'target',m.target,'money',m.reward_money,
    'xp',m.reward_xp,'progress',coalesce(um.progress,0),'claimed',coalesce(um.claimed,false)) order by m.kind, m.id), '[]'::jsonb)
  from missions m left join user_missions um on um.mission_id = m.id and um.user_id = u
    and um.period = case when m.kind='daily' then current_date else date_trunc('week',now())::date end),
 'achievements', (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'target',a.target,'money',a.reward_money,
    'n',coalesce(uc.n,0),'claimed',ua.user_id is not null) order by a.id), '[]'::jsonb)
  from achievements a left join user_counters uc on uc.user_id = u and uc.metric = a.metric
  left join user_achievements ua on ua.user_id = u and ua.achievement_id = a.id));
$$;

-- Hanya data publik: nama, level, tampilan, ikon kamar. Uang & inventaris tidak pernah ikut.
create or replace function friends_json(u uuid) returns jsonb language sql stable as $$
select jsonb_build_object(
 'code', (select code from characters where user_id = u),
 'friends', (select coalesce(jsonb_agg(jsonb_build_object('code',c.code,'name',c.name,'level',c.level,'skin',c.skin,'hair',c.hair,
    'shirt',c.shirt,'accessory',c.accessory,'room',(select coalesce(jsonb_agg(i.icon),'[]'::jsonb) from room_items r join items i on i.id = r.item_id where r.user_id = c.user_id))), '[]'::jsonb)
   from friends f join characters c on c.user_id = f.friend_id where f.user_id = u),
 'board', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (select name, level, skin, hair, shirt from characters order by xp desc limit 10) t));
$$;
revoke all on function bump(uuid,text), missions_json(uuid), friends_json(uuid) from public, anon, authenticated;

create or replace function game_action(p_user uuid, p_action text, p_arg text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c characters%rowtype; it items%rowtype; j jobs%rowtype; m missions%rowtype; a achievements%rowtype;
        h numeric; n int; f uuid; v jsonb;
begin
  insert into characters(user_id) values (p_user) on conflict do nothing;
  select * into c from characters where user_id = p_user for update;

  if c.sleep_start is null then
    h := least(extract(epoch from now() - c.updated_at) / 3600.0, 12);
    c.hunger := least(c.hunger, greatest(5, c.hunger - round(h*5)::int));
    c.energy := least(c.energy, greatest(5, c.energy - round(h*3)::int));
    c.clean  := least(c.clean,  greatest(5, c.clean  - round(h*3)::int));
    c.happy  := least(c.happy,  greatest(5, c.happy  - round(h*4)::int));
    c.social := least(c.social, greatest(5, c.social - round(h*2)::int));
    if c.hunger < 15 or c.clean < 15 then c.health := least(c.health, greatest(10, c.health - round(h*3)::int));
    else c.health := least(100, c.health + round(h)::int); end if;
  end if;
  c.updated_at := now();

  if c.sleep_start is not null and p_action in ('eat','bathe','play','social','sleep','work') then
    raise exception 'Karakter sedang tidur';
  end if;

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
    select * into j from jobs where id = p_arg;
    if not found then raise exception 'Pekerjaan tidak ada'; end if;
    if c.level < j.level_req then raise exception 'Level belum cukup'; end if;
    if now() < c.work_ready_at then raise exception 'Masih cooldown'; end if;
    if c.energy < j.energy_cost then raise exception 'Energi kurang'; end if;
    c.energy := c.energy - j.energy_cost; c.money := c.money + j.pay; c.xp := c.xp + j.xp; c.hunger := greatest(5, c.hunger - 5);
    c.work_ready_at := now() + make_interval(secs => j.cooldown_sec);
    insert into transactions(user_id,kind,amount,ref) values (p_user,'work',j.pay,j.id); perform bump(p_user,'work');
  elsif p_action = 'style' then
    if p_arg !~ '^(skin|hair|shirt):#[0-9a-fA-F]{6}$' then raise exception 'Gaya tidak valid'; end if;
    if split_part(p_arg,':',1) = 'skin' then c.skin := split_part(p_arg,':',2);
    elsif split_part(p_arg,':',1) = 'hair' then c.hair := split_part(p_arg,':',2);
    else c.shirt := split_part(p_arg,':',2); end if;
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

  c.level := 1 + c.xp / 100;
  update characters set name=c.name, skin=c.skin, hair=c.hair, shirt=c.shirt, accessory=c.accessory, last_daily=c.last_daily,
    level=c.level, xp=c.xp, money=c.money, hunger=c.hunger, energy=c.energy, clean=c.clean, happy=c.happy, health=c.health,
    social=c.social, sleep_start=c.sleep_start, work_ready_at=c.work_ready_at, updated_at=c.updated_at where user_id = p_user;

  v := case when p_action in ('missions','claim','claim_ach') then missions_json(p_user)
            when p_action in ('friends','friend_add','gift') then friends_json(p_user) end;
  return jsonb_build_object('character', to_jsonb(c), 'data', v,
    'room', (select coalesce(jsonb_agg(item_id), '[]'::jsonb) from room_items where user_id = p_user),
    'inventory', (select coalesce(jsonb_object_agg(item_id, qty), '{}'::jsonb) from inventory where user_id = p_user and qty > 0));
end $$;
revoke all on function game_action(uuid,text,text) from public, anon, authenticated;
grant execute on function game_action(uuid,text,text) to service_role;
