# ClassBar

A small macOS menu bar app that shows your current and next class, plus the
assignments coming up on Canvas.

## Install

Needs macOS 13 or later.

```sh
curl -fsSL https://raw.githubusercontent.com/nesetkab/classbar/main/install.sh | sh
```

This puts `ClassBar.app` in `~/Applications`, starts it, and sets it to open at
login. Look for the cat in your menu bar.

### From source

Needs the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/nesetkab/classbar.git
cd classbar
make install
```

## Set up

Click the cat, then the gear.

- **Calendar feed**: in Canvas, open Calendar and click Calendar Feed. Paste
  that link and press `test`. Treat it like a password.
- **Site**: your school's Canvas address, e.g. `https://school.instructure.com/`.
- **Dates**: first and last day of the term.
- **Classes**: add them by hand, or use `import from .ics…` with the calendar
  export from your school's registration system. Days accept `MWF`, `TuTh`,
  `Mon Wed`, and so on.

Press `save`. `schedule.example.json` shows the file the settings window
writes, if you would rather edit it directly.

## Use

- **Classes**: hover a card for details, click it to open the course in
  Canvas. The `zoom` pill opens the meeting link.
- **Assignments**: click one to open it in Canvas. Hover and click the circle
  on the right to mark it done.
- **Your own tasks**: click **+** and type something like `essay fri 5pm`. The
  due date is read from what you type.
- **Refresh**: the arrow re-fetches Canvas. It also refreshes on its own each
  time you close the menu.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/nesetkab/classbar/main/install.sh | sh -s uninstall
```

Or `make uninstall` if you built from source. Your settings stay in
`~/Library/Application Support/classbar` until you delete that folder.

## Development

```sh
make          # build/classbar
make test     # build and run the tests
make run      # run without installing
make dist     # build/ClassBar.zip, the file a release ships
```

Code lives in `src/`, tests in `tests/`, and the app bundle and launch agent
templates in `packaging/`.

## License

MIT
