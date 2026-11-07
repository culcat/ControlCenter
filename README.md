# Control Center (`aleksandr.control-center`)

Плагин **Control Center** для оболочки [Omarchy](https://omarchy.org) (`omarchy-shell` / Quickshell) в духе macOS Control Center (Bento-сетка) с полным сохранением системной палитры, типографики и скруглений активной темы Omarchy.

## Возможности

- **Иконка на верхней панели (Top Bar)**:
  - Векторная иконка двух переключателей в стиле macOS Control Center.
  - **ЛКМ** — открыть/закрыть Control Center.
  - **ПКМ** — быстрое выключение/включение звука (Mute).
  - **Колёсико мыши** — регулировка громкости с вызовом системного OSD.
- **Связь и сеть (Bento-карточка 2×2 слева)**:
  - **Wi-Fi**: быстрое включение/выключение по клику на иконку + встроенная страница выбора сети, ввода пароля и переключения DNS (`DHCP`, `Cloudflare`, `Google`).
  - **Bluetooth**: включение/выключение адаптера + встроенный список подключённых, сопряжённых и доступных устройств с поиском и индикацией заряда.
  - **VPN и Сеть**: отображение активного туннеля (`amn0`, `tun*`, `wg*`, `tailscale*`), локального IP и пинга.
- **Быстрые переключатели (Bento-карточки справа)**:
  - **Не беспокоить (DND)** — синхронизация с сервисом уведомлений Omarchy.
  - **Ночной свет (Night Light)** — управление цветовой температурой экрана (`hyprsunset`).
  - **Не спать (Stay Awake)** — блокировка автоперехода в скринсейвер и локскрин (`omarchy.idle`).
- **Питание и телеметрия**:
  - Сегментированный переключатель профилей питания (`Экономия`, `Баланс`, `Максимум`).
  - Живой мониторинг загрузки `CPU`, `RAM` и заряда батареи (`UPower`).
- **Экран и Звук (со встроенными подстраницами)**:
  - Слайдер яркости экрана + подстраница выбора масштаба монитора (`1x`, `1.25x`, `1.6x`, `2x`) и размера шрифта интерфейса (`10–20 px`).
  - Слайдер громкости + подстраница выбора устройства вывода, настройки микрофона и микшера громкости отдельных приложений (PipeWire).
- **Медиаплеер (Now Playing)**:
  - Управление активными MPRIS-плеерами (обложка трека, название, исполнитель, переключение между плеерами, `Prev` / `Play-Pause` / `Next`).
- **Нижняя панель быстрых действий**:
  - **Скриншот** (`omarchy-capture-screenshot`), **Запись экрана** (`omarchy-screenrecord`), **Стиль/Тема** (`omarchy-menu toggle style`), **Блокировка** (`omarchy-system-lock`).

## Установка

### Через менеджер плагинов Omarchy

```bash
omarchy plugin add https://github.com/culcat/ControlCenter.git --enable
```

### Вручную

Склонируйте репозиторий в `~/.config/omarchy/plugins/aleksandr.control-center`:

```bash
git clone git@github.com:culcat/ControlCenter.git ~/.config/omarchy/plugins/aleksandr.control-center
omarchy-shell shell rescanPlugins
omarchy plugin enable aleksandr.control-center
```

## Управление через IPC / Хоткеи

Вы можете привязать открытие Control Center или отдельных его разделов в `~/.config/hypr/bindings.lua`:

```bash
# Открыть / закрыть Control Center
omarchy-shell shell toggle aleksandr.control-center

# Открыть сразу нужный раздел (main | wifi | bluetooth | audio | display)
omarchy-shell aleksandr.control-center openPage audio
```

## Настройки (`~/.config/omarchy/shell.json`)

В секции `bar.layout.right` поддерживаются inline-параметры:

```json
{
  "id": "aleksandr.control-center",
  "showMediaAlways": true
}
```

## Лицензия

MIT
