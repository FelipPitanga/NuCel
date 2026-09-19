-- Cover the secondary foreign key used when filtering grants by device.
create index if not exists nucel_grants_device_id_idx
  on public.nucel_grants(device_id);
