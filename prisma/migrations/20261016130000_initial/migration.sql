-- UUIDs use PostgreSQL 17's built-in gen_random_uuid(). Application traffic must
-- use the hrm_app role; migrations run as the database owner.
CREATE TABLE tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  time_zone text NOT NULL DEFAULT 'UTC',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tenants_slug_format CHECK (slug ~ '^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$' OR slug ~ '^[a-z0-9]$')
);

CREATE TABLE auth_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email_normalized text NOT NULL UNIQUE,
  password_hash text,
  email_verified_at timestamptz,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT auth_accounts_email_normalized CHECK (email_normalized = lower(trim(email_normalized)))
);

CREATE TABLE teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, name)
);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  auth_account_id uuid REFERENCES auth_accounts(id) ON DELETE RESTRICT,
  origin_attendance_log_id uuid,
  staff_number text,
  display_name text,
  work_email text,
  status text NOT NULL DEFAULT 'provisional' CHECK (status IN ('provisional', 'active', 'inactive')),
  employment_status text,
  supervisor_user_id uuid,
  team_id uuid,
  hire_date date,
  ended_on date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, staff_number),
  UNIQUE (tenant_id, auth_account_id),
  UNIQUE (tenant_id, origin_attendance_log_id),
  FOREIGN KEY (tenant_id, supervisor_user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, team_id) REFERENCES teams(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT users_not_self_supervised CHECK (supervisor_user_id IS DISTINCT FROM id),
  CONSTRAINT users_active_identity CHECK (status <> 'active' OR (staff_number IS NOT NULL AND display_name IS NOT NULL AND employment_status IS NOT NULL AND hire_date IS NOT NULL)),
  CONSTRAINT users_provisional_no_login CHECK (status <> 'provisional' OR auth_account_id IS NULL)
);

CREATE TABLE permissions (
  key text PRIMARY KEY,
  description text NOT NULL,
  allowed_scopes text[] NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT permissions_scopes CHECK (allowed_scopes <@ ARRAY['own','team','all']::text[])
);

CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  name text NOT NULL,
  is_system_template boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, name)
);

CREATE TABLE role_permissions (
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  role_id uuid NOT NULL,
  permission_key text NOT NULL REFERENCES permissions(key) ON DELETE RESTRICT,
  scope text NOT NULL CHECK (scope IN ('own', 'team', 'all')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, role_id, permission_key, scope),
  FOREIGN KEY (tenant_id, role_id) REFERENCES roles(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE user_roles (
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  role_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, user_id, role_id),
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, role_id) REFERENCES roles(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  auth_account_id uuid NOT NULL REFERENCES auth_accounts(id) ON DELETE RESTRICT,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE login_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  email_normalized text NOT NULL,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE work_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  day_of_week integer NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_local_time time(0) NOT NULL,
  grace_minutes integer NOT NULL DEFAULT 0 CHECK (grace_minutes BETWEEN 0 AND 1440),
  absence_cutoff_local_time time(0) NOT NULL,
  effective_from date NOT NULL,
  effective_to date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT work_schedules_date_range CHECK (effective_to IS NULL OR effective_to >= effective_from)
);
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE work_schedules ADD CONSTRAINT work_schedules_no_overlap
  EXCLUDE USING gist (tenant_id WITH =, user_id WITH =, day_of_week WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&);

CREATE TABLE holidays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  holiday_date date NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, holiday_date)
);

CREATE TABLE devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  serial_number text NOT NULL,
  secret_hash text,
  name text,
  time_zone text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'disabled')),
  last_seen_at timestamptz,
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  CONSTRAINT devices_active_setup CHECK (status <> 'active' OR (secret_hash IS NOT NULL AND claimed_at IS NOT NULL))
);
CREATE UNIQUE INDEX devices_active_serial_number_key ON devices(serial_number) WHERE status = 'active';

CREATE TABLE device_user_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  device_id uuid NOT NULL,
  device_user_id text NOT NULL,
  user_id uuid NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_to timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, device_id) REFERENCES devices(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT device_user_mappings_date_range CHECK (effective_to IS NULL OR effective_to > effective_from)
);
CREATE UNIQUE INDEX device_user_mappings_current_key
  ON device_user_mappings(device_id, device_user_id) WHERE effective_to IS NULL;
CREATE INDEX device_user_mappings_lookup_idx ON device_user_mappings(tenant_id, device_id, device_user_id, effective_from);

CREATE TABLE attendance_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  device_id uuid NOT NULL,
  device_user_id text NOT NULL,
  user_id uuid,
  occurred_local timestamp(0) NOT NULL,
  device_time_zone text,
  occurred_at_utc timestamptz,
  received_at timestamptz NOT NULL DEFAULT now(),
  status_code text,
  verify_mode text,
  work_code text,
  raw_line text,
  event_key text NOT NULL,
  UNIQUE (tenant_id, id),
  UNIQUE (device_id, event_key),
  FOREIGN KEY (tenant_id, device_id) REFERENCES devices(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT attendance_logs_raw_line_length CHECK (raw_line IS NULL OR length(raw_line) <= 4096)
);
ALTER TABLE users ADD CONSTRAINT users_origin_attendance_log_fkey
  FOREIGN KEY (tenant_id, origin_attendance_log_id)
  REFERENCES attendance_logs(tenant_id, id) ON DELETE RESTRICT;
CREATE INDEX attendance_logs_device_pin_time_idx ON attendance_logs(tenant_id, device_id, device_user_id, occurred_at_utc);
CREATE INDEX attendance_logs_user_time_idx ON attendance_logs(tenant_id, user_id, occurred_at_utc);
CREATE INDEX attendance_logs_unresolved_idx ON attendance_logs(tenant_id, device_id, device_user_id, received_at) WHERE user_id IS NULL;

CREATE TABLE attendance_ingest_errors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  device_id uuid,
  received_at timestamptz NOT NULL DEFAULT now(),
  reason_code text NOT NULL,
  record_excerpt text,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, device_id) REFERENCES devices(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT attendance_ingest_errors_excerpt_length CHECK (record_excerpt IS NULL OR length(record_excerpt) <= 1024)
);

CREATE TABLE attendance_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  local_date date NOT NULL,
  schedule_id uuid,
  first_log_id uuid,
  first_clock_in_at timestamptz,
  effective_clock_in_at timestamptz,
  computed_status text NOT NULL CHECK (computed_status IN ('on_time', 'late', 'awaiting', 'absent', 'unresolved', 'not_scheduled')),
  effective_status text NOT NULL CHECK (effective_status IN ('on_time', 'late', 'awaiting', 'absent', 'unresolved', 'not_scheduled')),
  computed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, user_id, local_date),
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, schedule_id) REFERENCES work_schedules(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, first_log_id) REFERENCES attendance_logs(tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX attendance_days_status_idx ON attendance_days(tenant_id, local_date, effective_status);

CREATE TABLE attendance_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  local_date date NOT NULL,
  kind text NOT NULL CHECK (kind IN ('status', 'clock_in', 'both')),
  new_status text CHECK (new_status IN ('on_time', 'late', 'awaiting', 'absent', 'unresolved', 'not_scheduled')),
  new_clock_in_at timestamptz,
  reason text NOT NULL,
  actor_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  supersedes_id uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, supersedes_id),
  FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, actor_user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id, supersedes_id) REFERENCES attendance_adjustments(tenant_id, id) ON DELETE RESTRICT,
  CONSTRAINT attendance_adjustments_change CHECK (
    (kind = 'status' AND new_status IS NOT NULL AND new_clock_in_at IS NULL) OR
    (kind = 'clock_in' AND new_status IS NULL AND new_clock_in_at IS NOT NULL) OR
    (kind = 'both' AND new_status IS NOT NULL AND new_clock_in_at IS NOT NULL)),
  CONSTRAINT attendance_adjustments_reason CHECK (length(trim(reason)) > 0)
);
CREATE INDEX attendance_adjustments_history_idx ON attendance_adjustments(tenant_id, user_id, local_date, created_at);

CREATE TABLE audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  actor_user_id uuid,
  action text NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, actor_user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);
CREATE INDEX audit_events_tenant_time_idx ON audit_events(tenant_id, occurred_at);

-- Tenant isolation: every runtime transaction must SET LOCAL app.tenant_id to
-- the UUID resolved from the request host. No setting means no tenant rows.
DO $$ DECLARE table_name text; BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'teams','users','roles','role_permissions','user_roles','sessions',
    'login_invitations','work_schedules','holidays','devices',
    'device_user_mappings','attendance_logs','attendance_ingest_errors',
    'attendance_days','attendance_adjustments','audit_events'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = nullif(current_setting(''app.tenant_id'', true), '''')::uuid) WITH CHECK (tenant_id = nullif(current_setting(''app.tenant_id'', true), '''')::uuid)', table_name);
  END LOOP;
END $$;
