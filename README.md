# Soul Serve

Soul Serve connects kitchens with surplus food to nearby NGOs. This repository is a ground-up Flutter + Go replacement for the prototype preserved in [`old/`](old/).

## Architecture

```text
frontend/lib/
├── core/                 API configuration, HTTP client, theme
├── features/
│   ├── auth/             session state and authentication UI
│   ├── analytics/        role-aware bar, pipeline, and trend charts
│   ├── camera/           offline recognition modes and local history
│   ├── kitchen/          food logging, stats, forecast, history
│   ├── ngo/              nearby food, map, claims, delivery tracking
│   └── settings/         appearance and camera preferences
└── shared/               app shell, design-system widgets, page frame

backend/
├── cmd/api/              composition root and server lifecycle
├── internal/
│   ├── config/           validated environment configuration
│   ├── database/         embedded, versioned migrations
│   ├── domain/           application models
│   ├── httpapi/          REST transport and middleware
│   ├── service/          validation, auth, and use cases
│   └── store/postgres/   transactional PostgreSQL repository
├── migrations/           human-readable schema source
└── schema.sql            whole schema, for creating a new database
```

The API uses UUIDs, bcrypt password hashes, short and explicit role checks, consistent JSON errors, request-size limits, CORS allow-listing, and an atomic database transaction for claims. The Flutter app stores the access token in platform secure storage and keeps network and session state outside widgets.

## The control script

`./soulserve.sh` is an interactive front end for everything below — provisioning PostgreSQL, writing `.env`, running the API and the app together, and producing release artifacts. Run it with no arguments for a menu, or give it a subcommand to skip straight to a task.

```bash
./soulserve.sh              # menu
./soulserve.sh doctor       # what is installed, what is missing
./soulserve.sh db:setup     # create the role and database, apply the schema
./soulserve.sh run          # API and app in parallel, one ctrl-c stops both
./soulserve.sh build:apk    # release APK
./soulserve.sh --help       # every subcommand
```

`run` compiles and starts the API in the background with its log lines prefixed `[api]`, waits for `/api/health` to answer, then runs Flutter in the foreground so hot reload still works. It also picks the right API base URL for the target: `localhost` for desktop and web, `10.0.2.2` for an Android emulator, and an `adb reverse` tunnel or your LAN address for a physical handset. Build artifacts are written to `dist/`.

The manual instructions below remain accurate, and are worth reading once to understand what the script does on your behalf.

## Local setup without Docker

These instructions set up PostgreSQL, Android development, Chrome, the Go API, and the Flutter client on a new Linux or Windows development machine.

### Required versions

- Go 1.23 or newer
- PostgreSQL 15 or newer
- Flutter 3.24 or newer with Dart 3.5 or newer
- Android Studio with an Android SDK, or Google Chrome for web development

Install [Go](https://go.dev/doc/install) and [Flutter](https://docs.flutter.dev/get-started/install) before continuing. Add both executables to `PATH` as directed by their installers.

### Linux: install system dependencies

The commands below target Ubuntu and Debian:

```bash
sudo apt update
sudo apt install -y \
  postgresql postgresql-contrib \
  curl git unzip xz-utils zip libglu1-mesa \
  clang cmake ninja-build pkg-config libgtk-3-dev \
  libsecret-1-dev libjsoncpp-dev mesa-utils
sudo systemctl enable --now postgresql
```

This installs both the PostgreSQL server and `psql`. Installing only `postgresql-client-common` is not sufficient because the application needs a local database server.

Confirm that PostgreSQL created its operating-system account and started successfully:

```bash
psql --version
getent passwd postgres
sudo systemctl status postgresql --no-pager
```

If `postgres` is still missing, inspect the package installation with `apt policy postgresql` and rerun the installation command above.

#### Install Chrome on Linux

Download the current Debian/Ubuntu `.deb` package from [Google Chrome](https://www.google.com/chrome/), then install the downloaded file:

```bash
sudo apt install ./google-chrome-stable_current_amd64.deb
google-chrome --version
```

Use the matching ARM64 package instead on an ARM64 computer. Flutter should list Chrome after installation.

#### Install Android tooling on Linux

1. Install the latest stable [Android Studio](https://developer.android.com/studio).
2. Open Android Studio and select **More Actions → SDK Manager**.
3. Under **SDK Platforms**, install the latest stable Android SDK platform.
4. Under **SDK Tools**, install:
   - Android SDK Build-Tools
   - Android SDK Command-line Tools (latest)
   - Android Emulator
   - Android SDK Platform-Tools
   - CMake
   - NDK (Side by side)
5. Open **More Actions → Virtual Device Manager** and create an emulator.
6. Accept the SDK licenses and validate the installation:

```bash
flutter doctor --android-licenses
flutter doctor
flutter emulators
flutter devices
```

If Flutter cannot locate the SDK, add these lines to `~/.bashrc`, using the SDK location shown by Android Studio:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
```

Restart the terminal or run `source ~/.bashrc` afterward.

### Windows: install system dependencies

#### Install PostgreSQL on Windows

1. Download the Windows installer from the [official PostgreSQL download page](https://www.postgresql.org/download/windows/).
2. Install **PostgreSQL Server**, **Command Line Tools**, and optionally **pgAdmin**.
3. Keep port `5432`, remember the password assigned to the `postgres` administrator, and allow the installer to start the PostgreSQL service.
4. Add the PostgreSQL `bin` directory to the user or system `PATH`. Its usual location is:

```text
C:\Program Files\PostgreSQL\<version>\bin
```

Open a new PowerShell window and verify the installation:

```powershell
psql --version
Get-Service postgresql*
```

#### Install Chrome on Windows

Download and run the installer from [Google Chrome](https://www.google.com/chrome/). Open a new PowerShell window afterward and confirm that `flutter devices` lists Chrome.

#### Install Android tooling on Windows

1. Install the latest stable [Android Studio](https://developer.android.com/studio).
2. Use **More Actions → SDK Manager** to install the same SDK platform and SDK Tools listed in the Linux section, including **Android SDK Command-line Tools (latest)**.
3. Use **More Actions → Virtual Device Manager** to create an emulator.
4. Run:

```powershell
flutter doctor --android-licenses
flutter doctor
flutter emulators
flutter devices
```

Android Studio normally configures the SDK automatically. If Flutter cannot find it, create an `ANDROID_HOME` user variable pointing to the SDK directory, usually:

```text
C:\Users\<username>\AppData\Local\Android\Sdk
```

Add these entries to the user `Path`:

```text
%ANDROID_HOME%\platform-tools
%ANDROID_HOME%\cmdline-tools\latest\bin
```

Native Windows desktop builds additionally require Visual Studio with the **Desktop development with C++** workload. This is not required when targeting Android or Chrome.

### Create the Soul Serve database

#### Linux

Run each command from the normal shell. This avoids interactive `psql` commands consuming additional pasted lines:

```bash
sudo -u postgres psql -c "CREATE USER soulserve WITH PASSWORD 'soulserve';"
sudo -u postgres psql -c "CREATE DATABASE soulserve OWNER soulserve;"
sudo -u postgres psql -d soulserve -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

If the role or database already exists, that error is harmless; continue with the extension command.

Then create the tables:

```bash
psql "postgres://soulserve:soulserve@localhost:5432/soulserve?sslmode=disable" -f backend/schema.sql
```

`backend/schema.sql` is the flattened result of every file in `backend/internal/database/migrations`, so a database built from it is identical to one built by migrating — verified by diffing `pg_dump` output of both. Every statement is `CREATE ... IF NOT EXISTS`, so re-running it leaves existing data alone. The API also applies its embedded migrations on each boot, which is then a no-op. **When you add a migration, add the same change to `schema.sql`.**

`./soulserve.sh db:setup` does all of the above in one step.

#### Windows

Run these commands in PowerShell and enter the PostgreSQL administrator password when prompted:

```powershell
psql -U postgres -h localhost -c "CREATE USER soulserve WITH PASSWORD 'soulserve';"
psql -U postgres -h localhost -c "CREATE DATABASE soulserve OWNER soulserve;"
psql -U postgres -h localhost -d soulserve -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

The Go API applies the versioned table migrations automatically when it starts. Test the new connection from the normal shell, not from inside a `psql` prompt:

```bash
psql "postgres://soulserve:soulserve@localhost:5432/soulserve?sslmode=disable" -c "SELECT current_database();"
```

The same command works in PowerShell.

### Configure the application

From the repository root, create `.env`.

Linux:

```bash
cp .env.example .env
```

Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

Edit `.env` and replace `JWT_SECRET` with a random string containing at least 32 characters. Its default `DATABASE_URL` matches the local database created above. The API automatically reads this file during local development.

### Start the Go API

Linux terminal:

```bash
cd backend
go mod download
go run ./cmd/api
```

Windows PowerShell:

```powershell
cd backend
go mod download
go run ./cmd/api
```

Keep this terminal running. Confirm the API from another terminal:

```bash
curl http://localhost:8080/api/health
```

The response should contain `"status":"ok"`.

### Start Flutter

Fetch the packages first:

```bash
cd frontend
flutter pub get
flutter devices
```

Choose one of the following targets.

Linux desktop:

```bash
flutter run -d linux --dart-define=API_BASE_URL=http://localhost:8080/api
```

Chrome on Linux or Windows:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

Windows desktop:

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080/api
```

Android emulator:

```bash
flutter emulators --launch <emulator-id>
flutter run -d <device-id> --dart-define=API_BASE_URL=http://10.0.2.2:8080/api
```

Use the identifiers printed by `flutter emulators` and `flutter devices`. Android emulators use `10.0.2.2` to reach the host machine. For a physical Android device, use the development machine's LAN address and allow inbound TCP port `8080` in the firewall.

### Use the app

1. Register a **Food provider** account and include its latitude and longitude.
2. Sign out and register an **NGO** account with nearby coordinates.
3. As the food provider, log surplus food.
4. As the NGO, open the available-food list, claim the donation, then walk it through picked up, out for delivery, and delivered.

Using nearby coordinates allows the API to calculate and display the distance between the NGO and kitchen.

### App experience

- Phones use a bottom navigation bar; large screens use a persistent navigation rail that extends with labels past 1240px. Destinations switch in place and keep their scroll position, so the selected tab always reflects what is on screen.
- The Analytics screen presents role-specific food totals, a pending/claimed/delivered pipeline meter, and daily trends. Chart colors are drawn from validated tokens in `core/theme.dart` (`series` for single-series marks, `pipeline` for the ordinal ramp); re-validate before changing them. Pull down to refresh the underlying API data.
- NGOs can browse detailed nearby-food cards alongside an interactive OpenStreetMap. Selecting a map marker filters the visible donation cards.
- A claim is tracked through four stages — reserved, picked up, out for delivery, delivered — each stamped with its own timestamp and shown on a progress rail. Stages may be skipped forward but never reversed; a cancelled claim leaves the progression and shows no further action.
- Registration is a three-step wizard (account, organization, location) so no single page carries every field. Each step validates on its own, state survives going back, and a field rejected by the server reopens the step that owns it.
- Coordinates are picked by dragging an OpenStreetMap canvas under a fixed pin, or by geocoding the address already typed via OpenStreetMap Nominatim. Typing latitude and longitude by hand remains available behind a disclosure for keyboard and screen-reader users.
- Settings includes system, light, and dark appearance modes plus the default camera mode. Preferences persist locally on the device.
- Adding food uses a dedicated, validated screen with food-safety confirmations rather than a modal dialog.

The included OpenStreetMap public tile endpoint is appropriate for local development. Before a high-traffic production launch, configure a tile provider or self-hosted service that matches the expected volume and retain visible OpenStreetMap attribution.

### Offline food recognition

The centered camera action opens the food-recognition screen on Android and iOS. **Capture** mode analyzes one photo on demand. **Realtime** mode periodically analyzes the camera view and records newly recognized item groups. Recognition history is stored locally, can be cleared from the camera screen, and is not sent to the API. The default mode is configurable in Settings.

The current model performs broad image labeling and prioritizes food-related labels. It is suitable for assisting data entry, but its result should be confirmed by a person before a donation is published. The offline recognition feature requires Android 7.0/API 24 or newer, or iOS 15.5 or newer. Linux, Windows, and web builds display an explanatory mobile-only state while retaining the responsive camera navigation.

### Stop the local services

Stop Flutter and the Go API with `Ctrl+C` in their respective terminals. PostgreSQL can remain active, or it can be stopped with:

```bash
sudo systemctl stop postgresql
```

On Windows, PostgreSQL can be stopped and restarted from the Services application or with `Stop-Service postgresql*` and `Start-Service postgresql*` in an administrator PowerShell window. Application data remains in PostgreSQL between runs.

### Setup troubleshooting

- `psql: command not found`: install the complete PostgreSQL package on Linux or add PostgreSQL's `bin` directory to `PATH` on Windows.
- `sudo: user postgres not found`: the PostgreSQL server package was not installed successfully; `postgresql-client-common` alone does not create it.
- `cmdline-tools component is missing`: install **Android SDK Command-line Tools (latest)** from Android Studio's SDK Manager.
- Chrome is absent from `flutter devices`: install Chrome, restart the terminal, and rerun `flutter doctor`.
- `libsecret-1` build error on Linux: install `libsecret-1-dev` and `libjsoncpp-dev`, then run `flutter clean` and `flutter pub get`.

## API surface

| Area | Endpoints |
|---|---|
| Auth | `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/auth/me` |
| Kitchen | `POST /api/waste/log`, `GET /api/waste/my-logs`, kitchen stats/history |
| NGO | `GET /api/waste/available`, `POST /api/claims/{wasteID}/claim`, `PATCH /api/claims/{id}/status` with a `status` of `picked_up`, `out_for_delivery`, or `completed`, claim history/stats |
| Shared | `GET /api/dashboard/predictions`, `GET /api/health` |

Run checks with `make test`. Production deployments should terminate TLS at a load balancer, use a managed PostgreSQL database, rotate JWT secrets, and run migrations as a dedicated release step once concurrent replicas are introduced.
