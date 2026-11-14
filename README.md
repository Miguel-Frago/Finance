# Business Financial Monitoring (BFM)

Offline payroll and financial monitoring for Windows desktop and Android (tablet and phone).
Built with Flutter and a local SQLite database. No internet is needed to use it.

## What is included
- Puzzle lock ("connect the stars") with recovery code, auto-lock, audit trail, backup and restore, themes
- Employees (auto IDs), attendance (manual, time in/out buttons; fingerprint planned), rate and promotion history, performance reviews
- Payroll (daily, weekly, monthly, annual rates), deductions you configure, overtime, holidays, rest day, night differential, leave, loans, 13th month
- Payslips and reports as PDF with print preview (A4, Letter, Legal); logo and signature placeholders
- Dashboard with color-coded charts, customizable and printable; phone/tablet bottom navigation
- Renting and Financial Overview: "Coming Soon" (waiting for the business rules)

## Check that everything works (run in the project folder)
```
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```
- `flutter analyze` finds code problems. Info-level lines such as "deprecated" are fine; errors are not.
- `flutter test` runs the attendance and payroll calculation tests (about 16).
- Follow `TEST_CHECKLIST.md` to try each screen.

## Windows setup notes
- Install Visual Studio with the "Desktop development with C++" workload, and turn on Developer Mode
  (`start ms-settings:developers`).
- Windows Smart App Control can block the debug .exe. It has to be turned off to run debug builds.
- The first build downloads a PDF component for printing, so the PC needs internet that one time.

## Android build (phone and tablet)
1. Install Android Studio, then run `flutter doctor --android-licenses` and `flutter doctor -v`.
2. If the build stops with "requires libraries ... to compile against version 36", edit
   `android/build.gradle.kts` so the top of the file looks like this (the new block goes before
   the `evaluationDependsOn` block):
```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            compileSdk = 36
        }
    }
}
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
```
3. Build: `flutter build apk --release`
   The file is `build\app\outputs\flutter-apk\app-release.apk`. Copy it to the device and install it.

## Security notes
- The puzzle lock keeps casual users out. The database file is not encrypted yet.
- Keep the recovery code safe. There is no online reset.
- Each device keeps its own data (fully offline). Use Backup and Restore to move data.

## Fonts
PDF reports use Liberation Sans (SIL Open Font License 1.1, see `assets/fonts/LICENSE-LiberationSans.txt`).

## Business rules
Rates, percentages and rules (overtime, holidays, deductions, leave, loans, 13th month) are
starting values and are editable under Payroll rules. Update them once the company confirms its rules.
