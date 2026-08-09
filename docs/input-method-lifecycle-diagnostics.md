# Input Method Lifecycle Diagnostics

This document covers intermittent failures where McBopomofo cannot type in a
specific client application, or its input menu and preferences fail to appear.

The lifecycle log intentionally excludes composed text, key labels, candidate
contents, and surrounding document text.

## Investigation record

Recorded at `2026-08-09T03:51:26+08:00`:

- The installed input method was version 3.0, build 2264, installed on
  2026-08-02 local time.
- The McBopomofo process and `imklaunchagent` had remained alive for more than
  four days.
- No matching McBopomofo, `imklaunchagent`, or `TextInputMenuAgent` crash report
  was present.
- Unified logs captured during a working client session showed the normal
  `Activate Server`, `Set value`, `Menu`, input callback, and `Deactivate Server`
  sequence. A failing client session still needs to be captured.
- Lifecycle logging and the collection script described below compile in the
  main target. The diagnostic build has not yet been installed, so the currently
  running build does not emit the new lifecycle events.

Follow-up recorded at `2026-08-09T05:59:20+08:00`:

- The issue reproduced in a Messenger web app installed by Microsoft Edge.
- McBopomofo 3.0.1 build 2265 was running and its main thread was idle in the
  AppKit event loop. There was no crash or main-thread stall.
- Working ChatGPT sessions completed controller creation, activation, model
  loading, client callbacks, and key handling.
- The Messenger session did not establish a connection to McBopomofo. At the
  same time, `imklaunchagent` reported `Refusing connection name for bundle:
  unrecognized 'InputMethodConnectionName' value` twice.
- The Microsoft Edge main process had remained alive since before McBopomofo was
  reinstalled. Completely quitting Messenger and Microsoft Edge, then reopening
  Messenger, restored Chinese input without another McBopomofo installation.
- The confirmed failure boundary is therefore a stale client-side
  InputMethodKit session after the installer replaces and force-terminates the
  input method, rather than McBopomofo controller or key-handler execution.
- The immediate workaround is to restart the affected client application. A
  durable fix should investigate the installer replacement and process shutdown
  flow without introducing text-agent or preference-daemon restarts.

Installer fix implemented at `2026-08-09T06:08:39+08:00`:

- The installer now resolves the replacement bundle before removing the old
  bundle.
- During an upgrade, the old input method server remains alive until the new
  bundle has been copied back to its registered path. This removes the previous
  failure window where clients tried to reconnect while no bundle existed.
- The installer requests normal termination and waits up to three seconds. It
  only uses forced termination for a process that does not exit, waits another
  two seconds, and shows the existing restart warning if deactivation still
  cannot be confirmed.
- The installer does not restart `TextInputMenuAgent`, `cfprefsd`, or client
  applications.
- The `McBopomofoInstaller` Debug scheme builds successfully.

Acceptance test completed at `2026-08-09T06:46:47+08:00`:

- Microsoft Edge and the installed Messenger web app remained open while the
  updated installer replaced McBopomofo.
- The input method process changed from PID 4182 to PID 13234, and the new
  process completed `IMKServer` initialization.
- Messenger could immediately type Chinese without restarting Messenger or
  Edge. This confirms that restoring the bundle before terminating the old
  server prevents the stale client-session failure in the reproduced case.

## Capture a failure

1. Build and install the current development version with the
   `McBopomofoInstaller` scheme. Confirm that the old McBopomofo process has
   restarted.
2. When the problem appears, keep the affected application open and do not
   restart McBopomofo, `TextInputMenuAgent`, or the computer yet.
3. Record the affected application and approximate failure time.
4. From the repository root, run:

   ```bash
   AFFECTED_APP="Application Name" LOG_WINDOW=30m \
     Source/Tools/collect-input-method-diagnostics.sh
   ```

5. Preserve the generated `McBopomofo-input-diagnostics-*.log` file. It contains
   a short process sample, installed build metadata, related crash report names,
   and the relevant unified log window.

If the failure started more than 30 minutes ago, increase `LOG_WINDOW`, for
example to `2h`.

## Live lifecycle log

Use this command while reproducing the issue:

```bash
/usr/bin/log stream --style compact \
  --predicate 'subsystem == "org.openvanilla.inputmethod.McBopomofo" AND category == "InputMethodLifecycle"' \
  --info
```

## Event interpretation

| Last relevant event | Likely boundary |
| --- | --- |
| No `process_launch` for the installed build | The new build was not installed or its process was not restarted. |
| System `Activate Server`, but no `controller_init_end` | The controller did not finish construction or the callback did not reach our controller. |
| `activate_begin` without `activate_end` | Activation blocked. The last `activate_phase` narrows the call. |
| `set_value_begin` without `data_model_loaded` | Initial language-model loading blocked. |
| `menu_begin` without `menu_end` | Input menu construction or preference access blocked. |
| `preferences_menu_action` without `preferences_show_begin` | InputMethodKit did not forward the menu action to the app delegate. |
| `preferences_show_begin` without `preferences_show_end` | Preferences window creation or activation blocked. |
| `first_event_begin` without `client_attributes_received` | The client text-input callback blocked. |
| `client_attributes_received` without `key_handler_completed` | Key handling or a state transition blocked. |
| Complete lifecycle events, but the client still cannot type | Correlate the exact timestamp with `imklaunchagent` and client application logs. |

Events include a process session ID, controller ID, and activation sequence so
callbacks from different client sessions can be separated without recording
the client's text.
