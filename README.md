# Coding Limits

Нативное macOS-приложение в строке меню: показывает остатки лимитов **Kimi Coding** и **OpenCode Go**.

В строке меню `K 80·95  G 90·96·100` означает:

- `K` — окна Kimi Coding;
- `G` — 5 часов, неделя и месяц OpenCode Go;
- числа — процент оставшегося лимита.

В меню есть шкалы, время сброса и отдельные ошибки по каждому сервису. Обновление — раз в две минуты. Цвет становится оранжевым при остатке ≤20% и красным при ≤10%.

## Авторизация

Отдельный вход не нужен: приложение использует авторизацию CLI.

- **Kimi:** `/login` в Kimi Code CLI. Читается актуальный файл креденшелсов Kimi Code 2.4+: `$KIMI_CODE_HOME/credentials/kimi-code-env-*.json` (по умолчанию `~/.kimi-code/credentials/`), с fallback на старый путь `~/.kimi/credentials/kimi-code.json`. Истёкший OAuth-токен обновляется через тот же публичный OAuth client ID, что использует CLI; если в файле нет `expires_at`, обновление срабатывает при ответе 401. Можно переопределить токен через `KIMI_LIMITS_TOKEN` или `KIMI_API_KEY`. Показываются окна «5h» и «Month code».
- **OpenCode Go:** `/connect` в OpenCode. Приложение вызывает `opencode api GET /api/experimental/usage/limits`, поэтому токены не копируются и остаются в хранилище OpenCode. Нужны OpenCode CLI и запущенный штатный background service.

Приложение запрашивает только usage API, не отправляет промпты и не расходует квоту. Это неофициальный проект, не связанный с Moonshot AI или OpenCode; форматы API могут измениться.

## Сборка и установка

Нужны macOS 14+, Swift и установленные `kimi-code` / `opencode`.

```bash
./scripts/build-app.sh --install
```

Собирает `dist/Coding Limits.app`, заменяет `/Applications/Coding Limits.app` и запускает её. Без `--install` — только сборка.

## Проверка и диагностика

```bash
swift build
./.build/release/CodingLimitsMenuBar --snapshot
./.build/release/CodingLimitsMenuBar --raw
```

`--snapshot` печатает разобранные окна, `--raw` — ответы API. Токены в вывод не попадают.
