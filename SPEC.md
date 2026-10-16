# HRM SaaS product specification

**Status:** Working draft based on the client's attendance and access-control description  
**V1 focus:** Tenant-specific ZKTeco ADMS attendance collection and daily presence  
**Architecture:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## 1. Product goal

Each client gets an isolated HR workspace at its own subdomain. Client administrators manage staff, devices, schedules, and access. Supervisors open a daily attendance view to see who clocked in on time, who was late, and who is absent. Staff may view their own attendance when granted permission.

“Client,” “customer,” and “tenant” mean the same organization. A clock-in on a ZKTeco device is an attendance event; it is distinct from signing in to the web app.

## 2. Users, roles, and permissions

- A tenant has users, roles, and permission assignments. A user may have multiple roles within a tenant. Effective permissions are the union of those roles, subject to a data scope such as `own`, `team`, or `all`.
- Seed editable role templates named **Administrator**, **Supervisor**, and **Staff** for each tenant. Authorization checks permission keys and scope, never a role name. Tenants may create additional roles and change the permissions on their roles.
- Initial permission keys cover `users.manage`, `roles.manage`, `staff.read`, `staff.manage`, `devices.read`, `devices.manage`, `schedules.read`, `schedules.manage`, `attendance.read`, `attendance.adjust`, `attendance.export`, and `audit.read`. The implementation should keep permission keys stable even when role names change.
- The first client administrator can manage users, roles, devices, schedules, and attendance. A supervisor's default role reads and adjusts team attendance and reads team work profiles. A staff member's default role reads only their own attendance. These are initial templates, not fixed privileges.
- Prevent loss of the last active user able to manage tenant access. Changes to roles, assignments, and permissions are audited. Platform operators use a separate access path and do not gain routine access to staff data through tenant roles.

| Action | Administrator template | Supervisor template | Staff template |
| --- | --- | --- | --- |
| Manage users and roles | Yes | No | No |
| Manage devices, staff, schedules | Yes | No | No |
| View attendance | All staff | Assigned team | Own only |
| Adjust attendance | All staff | Assigned team | No |
| Export attendance | All staff | No | No |
| View tenant audit events | Yes | No | No |

## 3. V1 features

### 3.1 Client and user setup

- A platform operator creates a tenant slug and initial administrator. Self-service signup and billing are outside V1.
- The app resolves the tenant from the hostname. Unknown, suspended, or reserved subdomains do not expose client data.
- Administrators invite or deactivate web users, assign and remove roles, and link a tenant-local `users` record to a global login account. A `users` record can exist without a login account.
- Device punches for unknown device user IDs are saved first, then create provisional tenant users automatically. Provisional users cannot log in until an administrator verifies and activates them and links a login account. [Database structure](docs/DATABASE.md).
- Activated users can sign in, sign out, and recover access. The exact login method remains open. Login at a tenant subdomain requires an active tenant user linked to the authenticated account.

### 3.2 Staff, teams, and schedules

- Administrators create, edit, search, and archive tenant user records. For an activated staff record, required fields are staff number, name, employment status, and hire date. Provisional device-discovered users may lack these fields until reviewed. Optional fields: work email, department/team, supervisor, and end date.
- Staff number is unique within a tenant. Archiving preserves attendance history but removes the person from future expected-attendance lists.
- Administrators define the tenant time zone, working days, holidays, and each staff member's expected start time. V1 assumes one day schedule per staff member; shift rotations and overnight shifts remain open for later design.
- A supervisor's team consists of directly assigned staff. The application enforces team scope in each attendance and staff query, independently of UI visibility.

### 3.3 ZKTeco ADMS device management

- A device's first handshake appears as a pending device under the tenant identified by its subdomain. An administrator verifies its serial number and ownership, sets its display name, location, and time zone, then claims it. The configured secret is stored as a verifier, not displayed back to users. A serial number cannot be active in two tenants; an unknown or wrong-tenant hostname cannot claim it automatically.
- The device's ADMS server is configured to point to that tenant's subdomain. On firmware that accepts a URL path, configure a device-specific secret as a path segment. The server checks the resolved tenant, registered device serial number, device status, and secret before accepting data. A request with a valid serial number and secret on another tenant's hostname still fails.
- Show last contact time, last accepted event time, configured device time zone, and device status in the administrator UI. Administrators can disable a device; disabled devices cannot add attendance records.
- Map each device user ID to a tenant user. If an unknown ID sends a punch, save the raw punch with no user link, then create a provisional user and mapping for that device ID. Show it to administrators for identity review; never merge matching IDs across devices automatically.
- The V1 integration receives attendance transactions and required device polling/handshake traffic. It does not manage biometric templates, photos, firmware, door access, or device commands unless a verified model requires a narrow command for attendance delivery.
- Keep the protocol adapter separate from attendance rules. Capture device model, firmware, selected push mode, and sample traffic before finalizing endpoint paths, formats, responses, and retry behavior. ZKTeco documents domain-based ADMS server configuration and distinguishes attendance push from access-control push on some models. [ZKTeco FAQ](https://www.zkteco.com/en/faq.html), [ZKTeco F35 product details](https://www.zkteco.com/en/FSeries/F35).

**ADMS URL design:** The local [skylinebiz/adms reference](https://github.com/skylinebiz/adms) mounts `/:companySlug/:secret/iclock` and documents devices appending `/iclock/cdata`, `/iclock/getrequest`, and other suffixes to the configured base URL. Our V1 candidate is `https://<tenant>.<base-domain>/<device-secret>`, yielding requests such as `GET /<device-secret>/iclock/cdata?SN=...` and `POST /<device-secret>/iclock/cdata?SN=...&table=ATTLOG`. The hostname identifies the tenant; the serial number and secret identify the registered device. The adapter must still check that the device belongs to the hostname's tenant. If a target model accepts only a hostname and port, use a device-supported credential or a private gateway while keeping the tenant subdomain. Never put secrets in browser pages or normal request logs; store only a verifier or hash and support rotation. The route shape and response details remain subject to a real target-device test.

### 3.4 Punch ingestion

- Support the minimum observed protocol exchange: `GET cdata` handshake returns plain-text configuration, `GET getrequest` returns plain-text `OK` when there are no commands, and `POST cdata?table=ATTLOG` returns plain-text `OK` only after accepted punches are stored. Add `POST devicecmd`, `/test`, or `.aspx` variants only when the selected models require them. Parse and validate supported device messages; accept only a known tenant/device combination and enforce request size limits.
- For each ATTLOG punch, record device user ID, original device-local wall-clock value, configured device time zone, derived UTC instant, receive timestamp, status/verification fields, and device identity. Do not infer UTC from the WSL server's time zone. A device with no confirmed time zone must be flagged for setup before its punches determine attendance status.
- Persist accepted punch events before sending a successful protocol response, even when no internal user exists or the user-creation step fails. `attendance_logs.user_id` is nullable; automatic user creation and log linking are retryable after ingestion. Retries and repeated batches must not create duplicate punches. Store an ingestion key or equivalent deduplication evidence per device event.
- While a device is pending, acknowledge only the handshake and polling traffic needed for discovery. Withhold a success acknowledgement for data-bearing attendance batches until the device is claimed, so stored punches are not silently lost. Test the retry behavior on the target firmware.
- Derive the local attendance date using the tenant time zone after converting the device-local time to UTC. Flag clock skew and events arriving after the day was first calculated; recompute affected daily status when late data arrives.
- Unsupported or malformed messages produce a protocol-appropriate response and a diagnostic record without exposing another tenant's data. Determine whether to acknowledge or retry each message type so firmware cannot get stuck retrying forever or silently lose attendance data. Do not collect biometric templates or images in V1.
- Device connectivity and delivery failures are visible to administrators. A device being offline must be shown separately from a conclusion that a person was absent.

### 3.5 Daily attendance

- For each scheduled, active staff member and local date, classify **on time**, **late**, **absent**, or **unresolved**. A nonworking day is **not scheduled**. A person with no usable schedule or an unmapped punch is **unresolved**, never automatically absent.
- V1's provisional rule uses the first valid clock-in: on time if it is at or before expected start plus grace minutes; late if after that threshold. If no valid clock-in exists after a configurable absence cutoff, mark absent. Before the cutoff, show **awaiting clock-in** rather than absent.
- The daily view shows counts and staff lists by status, scheduled start, first clock-in, lateness, source device, and any warning about stale device data. Supervisors see only their team; users with all-staff scope may filter by date, team, staff, and status.
- Supervisors with `attendance.adjust` and `team` scope can adjust attendance for direct reports; administrators with `all` scope can adjust any tenant user. An adjustment requires a reason, actor, and time. Keep raw device events unchanged and show correction history. Recalculation must be deterministic and honor a valid adjustment.
- A monthly calendar shows each visible user's daily statuses, first clock-in, any adjustment, and counts for on-time, late, absent, and unresolved days. Scope checks apply to both monthly rows and totals.
- Export the visible, permission-scoped attendance list as CSV. Dates and times follow the tenant time zone, and exports identify whether a row was corrected.

## 4. Core workflows and acceptance criteria

1. **Provision a client:** Create `acme`; `acme.<base-domain>` resolves only to Acme. An unknown or suspended subdomain cannot access Acme pages or ADMS ingestion.
2. **Assign access:** An administrator creates a custom role with `attendance.read` scoped to `team` and assigns it to a supervisor. The supervisor can see direct reports but receives a forbidden response for another team's records and exports.
3. **Enroll device:** Point a device at Acme's subdomain with a configured secret. Its first handshake appears as pending under Acme. An administrator verifies the serial number and ownership, sets the device time zone, and claims it, then maps a device user ID to an Acme staff member. Requests to a different tenant hostname with that serial number and secret are rejected and never create staff punches there.
4. **Receive punch:** A supported device uploads a clock-in. The event is persisted once, even if the device retries or no user exists yet. An unknown device user ID produces a provisional user and appears in an administrator review queue; the original punch links to that user after reconciliation.
5. **Review day:** A supervisor sees on-time, late, awaiting, absent, and unresolved staff for the chosen date. Absence is shown only after the cutoff; an offline device warning is visible alongside affected data.
6. **Adjust record:** A supervisor adjusts a direct report's attendance with a reason. Raw punch history remains visible to authorized users; daily and monthly status and CSV output reflect the adjustment. Audit history identifies who changed it and when. A supervisor cannot adjust another team's user.
7. **Enforce isolation:** Cross-tenant staff, device, mapping, event, schedule, role, and attendance access fails at both the HTTP layer and database policy layer.

## 5. Data and processing rules

- Tenant-owned tables include tenant ID: users, roles, role permissions, user-role assignments, teams, schedules, holidays, devices, device-user mappings, raw punch events, daily attendance results, and adjustments. Unique constraints and foreign keys include tenant scope where needed. The table design is in [docs/DATABASE.md](docs/DATABASE.md).
- Store a punch's original wall-clock value and device time zone alongside the derived UTC timestamp. Use tenant-local calendar dates for reports. A schedule rule is versioned or effective-dated so later changes do not silently reinterpret historical attendance.
- Treat daily results as derived data that can be recalculated from punches, schedules, holidays, and corrections. Keep ingestion idempotent and preserve an audit trail for edits.
- Attendance list queries and exports require permission plus `own`, `team`, or `all` data scope. An auth account without an active linked tenant user cannot use `own` attendance access.
- Protect tenant records with application scoping and PostgreSQL row-level security before production, as specified in the architecture plan.

## 6. Security and quality gates

- All web APIs enforce session, active tenant user, permission, and data scope on the server. Device ingress uses a separate authentication path, tenant resolution, and device enrollment check.
- Use HTTPS when the selected device firmware supports it. If hardware cannot securely reach a public endpoint, design a private network or gateway arrangement before connecting it to production. The exact capability must be tested on the chosen devices; ZKTeco's guidance varies by model and software configuration. [ZKTeco FAQ](https://www.zkteco.com/en/faq.html).
- Rate-limit and bound ADMS requests; monitor rejected serial numbers, malformed payloads, clock drift, ingestion lag, and device silence. Avoid logging full raw payloads that may contain sensitive fields.
- Test protocol exchanges against at least one real target model/firmware and captured retry examples, in addition to unit and integration tests. Test late delivery, duplicate delivery, missing mappings, incorrect host, suspended device, time-zone boundaries, and permission scope.

## 7. Development environment

- The development app and PostgreSQL run on this Debian-based WSL device. Detected: Node.js 24, npm 11, PostgreSQL client 17, and PostgreSQL cluster `17/main`.
- A project-local PostgreSQL 17 cluster, `hrm_dev` database, and restricted `hrm_app` role now exist. The SQL migration is applied. This restricted task shell cannot open sockets, so the cluster is stopped here; start it from a normal WSL shell as described in the [README](README.md). Prisma package installation and CLI validation await npm registry access. [PostgreSQL readiness command](https://www.postgresql.org/docs/17/app-pg-isready.html).
- Use two local tenant hostnames for web and ADMS integration tests. The device must be able to resolve and reach the WSL-hosted endpoint; the network path, certificate support, and port configuration will be validated with the actual model. Automated HTTP tests set the `Host` header explicitly.
- Document exact development, test, build, database, and migration commands when the app is scaffolded.

## 8. Outside V1

Leave management, payroll, recruiting, performance reviews, timesheets and worked-hour totals, overtime, shift rotations, overnight shifts, biometric enrollment, remote device configuration, firmware updates, door/access-control management, mobile apps, billing, custom domains, and non-ZKTeco integrations are deferred.

## 9. Decisions to confirm

1. Target ZKTeco models, firmware versions, and available ADMS protocol documentation or request samples. Confirm attendance push mode, HTTPS capability, whether the device accepts a URL path, and whether it uses bare or `.aspx` protocol endpoints.
2. Scheduling model: fixed start per staff member, per-day shifts, or another rule; grace minutes and absence cutoff.
3. Whether V1 needs clock-out and early-departure reporting. The current daily view uses first clock-in only.
4. Login method and initial permission catalog; decide whether tenants can create custom permission keys or only assign predefined keys. This draft assumes predefined keys.
5. Confirm provisional auto-created users and whether supervisor adjustments take effect immediately. The database design assumes both.
6. Production hosting and device-to-server network path. Local WSL hosting is established for development only.
