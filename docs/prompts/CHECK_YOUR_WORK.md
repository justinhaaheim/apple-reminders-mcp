# Check your work

Check your work with `npm run signal`:

- `npm run signal` - Check for typescript, lint and formatting issues all at once

You can also use these scripts to directly check for issues:

- `npm run ts-check` - Check for typescript errors
- `npm run lint` - Check for lint issues

You can also use the tools directly via `npx`:

- `npx tsc --noEmit [file]`
- `npx eslint [file]`

Do NOT use `cd [path] && [command]` in your commands unless it is absolutely necessary. `cd` commands are blocked by default and require explicit permission, which slows us both down.
