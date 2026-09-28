-- KisahAbadi · jalankan seluruh file ini di Supabase > SQL Editor
create table packages(id bigint generated always as identity primary key,name text not null,tagline text,price int not null,max_hours int not null,features text,sort_order int default 0,is_active boolean default true);
create table units(id bigint generated always as identity primary key,name text not null,status text not null default 'available' check(status in('available','booked','maintenance','inactive')),notes text);
create table bookings(id bigint generated always as identity primary key,customer_name text not null,whatsapp text not null,event_date date not null,package_id bigint not null references packages(id) on delete restrict,unit_id bigint references units(id) on delete set null,event_type text,start_time time not null,end_time time not null,location text,notes text,status text not null default 'pending' check(status in('pending','confirmed','completed','cancelled')),created_at timestamptz default now());
create index on bookings(event_date,status);
create table testimonials(id bigint generated always as identity primary key,image text not null,customer_name text not null,message text,show_home boolean default true,created_at timestamptz default now());
create table portfolio(id bigint generated always as identity primary key,image text not null,title text not null,category text not null default 'Wedding' check(category in('Prewedding','Siraman','Akad','Resepsi','Wedding')),created_at timestamptz default now());

alter table packages enable row level security;alter table units enable row level security;alter table bookings enable row level security;alter table testimonials enable row level security;alter table portfolio enable row level security;
create policy pub_read on packages for select to anon using(is_active);
create policy pub_read on testimonials for select to anon using(true);
create policy pub_read on portfolio for select to anon using(true);
create policy admin_all on packages for all to authenticated using(true) with check(true);
create policy admin_all on units for all to authenticated using(true) with check(true);
create policy admin_all on bookings for all to authenticated using(true) with check(true);
create policy admin_all on testimonials for all to authenticated using(true) with check(true);
create policy admin_all on portfolio for all to authenticated using(true) with check(true);

-- Inti logika booking + anti double booking (dipakai pelanggan & admin)
create function _book(p_id bigint,p_name text,p_wa text,p_date date,p_package bigint,p_type text,p_start time,p_end time,p_loc text,p_notes text,p_status text,p_admin boolean) returns bigint language plpgsql security definer set search_path=public as $$
declare pk packages;u bigint;wa text:=regexp_replace(coalesce(p_wa,''),'\D','','g');
begin
 if left(wa,1)='0' then wa:='62'||substr(wa,2);end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Nama wajib diisi.';end if;
 if length(wa)<10 or length(wa)>15 then raise exception 'Nomor WhatsApp tidak valid.';end if;
 if not p_admin and p_date<(now() at time zone 'Asia/Jakarta')::date+1 then raise exception 'Booking maksimal H-1 (mulai besok).';end if;
 if p_start<time '06:00' or p_end>time '22:00' or p_end<=p_start then raise exception 'Jam harus antara 06.00–22.00 dan jam selesai setelah jam mulai.';end if;
 select * into pk from packages where id=p_package and(is_active or p_admin);
 if not found then raise exception 'Pilih paket.';end if;
 if extract(epoch from(p_end-p_start))/3600.0>pk.max_hours then raise exception 'Durasi melebihi maksimal paket % (% jam).',pk.name,pk.max_hours;end if;
 if p_status in('pending','confirmed') then
  perform pg_advisory_xact_lock(hashtext(p_date::text));
  select id into u from units where status in('available','booked') and not exists(select 1 from bookings b where b.unit_id=units.id and b.event_date=p_date and b.status in('pending','confirmed') and b.start_time<p_end and b.end_time>p_start and b.id is distinct from p_id) order by id limit 1;
  if u is null then raise exception 'Maaf, jadwal tersebut sudah terbooking. Silakan pilih waktu atau tanggal lainnya.';end if;
 end if;
 if p_id is null then insert into bookings(customer_name,whatsapp,event_date,package_id,unit_id,event_type,start_time,end_time,location,notes,status) values(trim(p_name),wa,p_date,p_package,u,p_type,p_start,p_end,p_loc,p_notes,p_status) returning id into p_id;
 else update bookings set customer_name=trim(p_name),whatsapp=wa,event_date=p_date,package_id=p_package,unit_id=u,event_type=p_type,start_time=p_start,end_time=p_end,location=p_loc,notes=p_notes,status=p_status where id=p_id;end if;
 return p_id;
end$$;
revoke all on function _book(bigint,text,text,date,bigint,text,time,time,text,text,text,boolean) from public,anon,authenticated;
create function create_booking(p_name text,p_wa text,p_date date,p_package bigint,p_type text,p_start time,p_end time,p_loc text,p_notes text) returns bigint language sql security definer set search_path=public as $$select _book(null,p_name,p_wa,p_date,p_package,p_type,p_start,p_end,p_loc,p_notes,'pending',false)$$;
create function admin_save_booking(p_id bigint,p_name text,p_wa text,p_date date,p_package bigint,p_type text,p_start time,p_end time,p_loc text,p_notes text,p_status text) returns bigint language plpgsql security definer set search_path=public as $$
begin if auth.uid() is null then raise exception 'Unauthorized';end if;return _book(p_id,p_name,p_wa,p_date,p_package,p_type,p_start,p_end,p_loc,p_notes,p_status,true);end$$;
-- Data publik untuk kalender (tanpa data pribadi pelanggan)
create function public_busy(d1 date,d2 date) returns table(event_date date,start_time time,end_time time,unit_id bigint,pkg text) language sql stable security definer set search_path=public as $$
select b.event_date,b.start_time,b.end_time,b.unit_id,p.name from bookings b join packages p on p.id=b.package_id where b.event_date between d1 and d2 and b.status in('pending','confirmed')$$;
create function public_units() returns setof bigint language sql stable security definer set search_path=public as $$select id from units where status in('available','booked')$$;
revoke all on function create_booking(text,text,date,bigint,text,time,time,text,text),public_busy(date,date),public_units(),admin_save_booking(bigint,text,text,date,bigint,text,time,time,text,text,text) from public,anon,authenticated;
grant execute on function create_booking(text,text,date,bigint,text,time,time,text,text),public_busy(date,date),public_units() to anon,authenticated;
grant execute on function admin_save_booking(bigint,text,text,date,bigint,text,time,time,text,text,text) to authenticated;

-- Storage gambar (testimoni & portfolio)
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('images','images',true,3145728,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy img_read on storage.objects for select using(bucket_id='images');
create policy img_ins on storage.objects for insert to authenticated with check(bucket_id='images');
create policy img_upd on storage.objects for update to authenticated using(bucket_id='images');
create policy img_del on storage.objects for delete to authenticated using(bucket_id='images');

insert into packages(name,tagline,price,max_hours,features,sort_order) values
('Bloom','Before the vows, there are stories worth remembering',200000,2,E'Prewedding – Siraman\n2 Story Editing Real-Time',1),
('Cherish','For the moment you say ''I do''',300000,4,E'Akad Only\n5 Story Editing Real-Time',2),
('Lumiere','From ''I do'' to the celebration of forever',400000,8,E'Akad + Resepsi\n10+ Story Editing Real-Time',3);
insert into units(name) values('Unit 1 – iPhone 13');
