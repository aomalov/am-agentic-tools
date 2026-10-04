# brew-to-macports — русский каталог сообщений.
#
# Формат: ключ = текст. Подстановки в стиле printf (%s), одинаковые для bash и
# python, поэтому строка живёт здесь один раз независимо от того, какая половина
# инструмента её печатает.
#
# База — en.msg; ключ, которого здесь нет, напечатается по-английски, а не
# пустой строкой.

# ------------------------------------------------------------------ usage ---
usage.title     = upgrade-vendor-packages — вендорские бинарники вместо сборки из исходников в brew
usage.all       = проверить и обновить всё
usage.check     = только отчёт, ничего не менять
usage.only      = работать только с этими
usage.patch     = брать и патч-релизы тоже
usage.rollback  = откатить на предыдущую версию
usage.list      = что установлено сейчас
usage.preflight = только проверка brew, без обновлений
usage.macports  = глубокая проверка готовности MacPorts
usage.bootstrap = новая машина: что куда переезжает
usage.tools     = Инструменты:
usage.prefix    = Префикс:
usage.symlinks  = (симлинки в %s)
usage.body1     = Обычный запуск делает всё разом: вендорские бинарники, cask'и из brew,
usage.body2     = предполётную проверку brew, обновление портов MacPorts (спросит пароль sudo)
usage.body3     = и сверку появившихся архивов.
usage.body4     = MacPorts обновляется строго через port -b (binary-only): порт без архива под
usage.body5     = нашу платформу останется необновлённым, но компилироваться ничего не будет.
usage.casks     = Приложения из brew с политикой «только мажор»:
usage.casks1    = Они закреплены через brew pin, поэтому brew upgrade их не трогает вообще.
usage.casks2    = Этот скрипт снимает закрепление только ради мажорного апгрейда и возвращает
usage.casks3    = обратно. --include-patch берёт для них и минорные, и патч-релизы.

# ------------------------------------------------------------------ errors --
err.unknown_arg  = неизвестный аргумент: %s
err.unknown_arch = неподдерживаемая архитектура: %s
err.no_tool      = нет утилиты: %s
err.no_py        = нет %s
err.no_bindir    = %s: не нашёл %s
err.no_tool_name = не знаю инструмент: %s
err.no_version   = %s: не удалось узнать версию у вендора
err.install      = %s: установка сорвалась, старая версия не тронута
err.symlinks     = %s: не смог проставить симлинки
err.ffmpeg_arch  = ffmpeg: evermeet.cx собирает только под Intel, а тут %s
err.gcloud_upd   = gcloud: components update не прошёл, каталог остаётся на %s
err.no_previous  = %s: нет предыдущей версии для отката (сейчас %s)
err.nothing      = ничего

# ------------------------------------------------------- vendor binaries ----
vendor.head        = Вендорские бинарники · %s · darwin %s
vendor.checkmode   = режим проверки — ничего меняться не будет
vendor.pruned      = убрал старую версию %s %s
vendor.rolled_back = %s: откатил %s → %s
vendor.not_present = не установлен → %s
vendor.latest      = уже последняя (%s)
vendor.ours_newer  = у вендора %s, у нас новее (%s)
vendor.patch       = %s → %s (патч)
vendor.patch_skip  = %s → %s — только патч, пропускаю
vendor.minor       = %s → %s (минор)
vendor.major       = %s → %s (МАЖОР)
vendor.odd_version = непонятная версия: %s vs %s
vendor.unpacked    = версия %s уже распакована, переключаю симлинки
vendor.downloading = качаю...
vendor.ready       = %s %s готов
vendor.gcloud_inplace = обновляю на месте через gcloud components update

# ----------------------------------------------------------------- summary --
sum.would_install = (был бы установлен)
sum.installed     = установлен
sum.skipped_patch = пропущен как патч (--include-patch чтобы взять)
sum.request_error = — ошибка запроса
sum.install_error = — ОШИБКА установки
sum.symlink_error = — ОШИБКА симлинков

# ----------------------------------------------------------------- shim -----
shim.format = rsvg-convert (resvg): формат '%s' не поддерживается — resvg отдаёт только png

# --------------------------------------------------------------- MacPorts ---
mp.head_upgrade   = MacPorts · обновление портов
mp.head_watch     = MacPorts · слежение за архивами
mp.head_ready     = MacPorts · готовность архивов
mp.checkmode      = режим проверки: дерево портов не обновляю, смотрю текущее состояние
mp.selfupdate     = обновляю дерево портов...
mp.no_root        = MacPorts: нет прав root и нечем спросить пароль
mp.run_manually   = выполни вручную: sudo port selfupdate && sudo port -b upgrade outdated
mp.selfupdate_bad = MacPorts: selfupdate не отработал, продолжаю со старым деревом
mp.upgrading      = обновляю (binary-only, сборки из исходников не будет)...
mp.upgrade_failed = %s: обновить не удалось
mp.sum_upgraded   = обновлено портов: %s
mp.sum_failed     = не обновились:%s
mp.pruning        = убираю неактивные версии портов: %s
mp.pruned         = неактивные версии сняты
mp.prune_failed   = MacPorts: неактивные версии снять не удалось
mp.archive_yes    = архив есть
mp.archive_wait   = ждём архив
mp.cached_today   = (данные за сегодня; --macports — проверить заново и глубоко)

# ------------------------------------------------------------------- brew ---
brew.head_preflight = Предполётная проверка Homebrew
brew.head_holders   = Homebrew · кто ещё держит формулы
cask.head           = Приложения из brew · только мажорные версии
cask.no_data        = %s: brew не отдал данные о cask'е
cask.not_installed  = не установлен
cask.install_hint   = поставить: brew install --cask %s
cask.latest         = уже последняя (%s)
cask.ours_newer     = в кране %s, у нас новее (%s)
cask.major          = %s → %s (МАЖОР)
cask.taken_patch    = %s → %s (%s, взято из-за --include-patch)
cask.not_major      = %s → %s — не мажор, пропускаю
cask.odd_version    = непонятная версия: %s vs %s
cask.would_upgrade  = (был бы обновлён)
cask.unpinning      = снимаю закрепление и обновляю...
cask.upgraded       = %s %s готов
cask.upgrade_failed = %s: brew upgrade сорвался
cask.pinned         = закреплён
cask.pinned_note    = закреплён: brew upgrade его больше не тронет
cask.not_pinned     = %s не закреплён — обычный запуск сделает brew pin --cask %s
cask.pin_failed     = %s: не удалось закрепить (brew pin --cask %s)
cask.sum_skipped    = пропущен: не мажор (--include-patch чтобы взять)
cask.sum_upgraded   = обновлён
cask.sum_error      = — ОШИБКА обновления

# ------------------------------------------------------------------- list ---
list.head   = Установлено в %s
list.empty  = пусто
list.header = ИНСТРУМЕНТ   ВЕРСИЯ           ОБНОВЛЁН             ПУТЬ

# -------------------------------------------------------------- bootstrap ---
boot.head        = Новый переезд · инвентаризация
boot.platform    = платформа:
boot.macports    = MacPorts:
boot.mp_prefix   = (префикс %s)
boot.mp_missing  = не установлен
boot.mp_skipped  = — шаг 2 будет пропущен
boot.mp_pkg      = pkg под эту macOS: https://www.macports.org/install.php
boot.state       = вендоров в state.tsv:
boot.config      = конфиг:
boot.no_config   = не найден
boot.defaults    = — работают значения по умолчанию
boot.no_brew     = Homebrew на этой машине нет — переезжать не с чего

# ----------------------------------------------------------- fresh machine --
fresh.warn   = вендорских настроек нет — похоже, это новая машина
fresh.hint1  = запусти сначала: %s --bootstrap
fresh.hint2  = он ничего не меняет, только покажет, что куда переезжает
fresh.hint3  = потом вернись сюда, или попроси скилл brew-to-macports провести за руку

# ----------------------------------------------------------------- result ---
result.head    = Итог
result.nothing = всё актуально, делать нечего

# ------------------------------------------- MacPorts: отчёт об устаревших ---
mpr.up_to_date    = порты в актуальном состоянии
mpr.outdated      = требуют обновления: %s
mpr.archive_yes   = архив есть:
mpr.archive_no    = архива под нашу платформу нет:
mpr.skipped_by_b  = их -b пропустит; обновятся, когда buildbot доедет
mpr.uncheckable   = не удалось проверить:

# ----------------------------------------------- MacPorts: список слежения ---
mpc.nothing_left  = переезжать из brew больше нечего
mpc.remaining     = в brew осталось формул: %s, cask'ов: %s
mpc.held_by_cask  = %s держит cask %s — переехать не может,
mpc.held_note     = cask завязан именно на брюшную формулу; остальное это его обвязка
mpc.target        = цель: %s   портов под наблюдением: %s
mpc.why_building  = brew УЖЕ собирает из исходников
mpc.why_bottle    = brew пока льёт бутылку
mpc.why_absent    = в brew не установлено
mpc.new           = ← НОВОЕ
mpc.has_archive   = архив %s
mpc.no_mp_compare = MacPorts не установлен — с версией в дереве не сверял
mpc.stale_archive = архив есть, но не под версию из дерева
mpc.need_selfupd  = нужен sudo port selfupdate, иначе port будет СОБИРАТЬ
mpc.on_server     = на сервере: %s
mpc.no_archive    = архива нет
mpc.deep_head     = Глубокая проверка: готовность дерева зависимостей
mpc.deep_ports    = %s/%s портов
mpc.deep_waiting  = ждём: %s
mpc.deep_waiting_n = ждём ещё %s, в т.ч.: %s
mpc.ready_title   = Готово к переезду в MacPorts: %s
mpc.mp_missing    = MacPorts ещё не установлен:
mpc.mp_step1      = 1. pkg под macOS %s: https://www.macports.org/install.php
mpc.mp_step2      = 2. sudo port selfupdate
mpc.pulls_in      = потянет за собой портов: %s
mpc.say_migrate   = Скажи «переезжаем %s»
mpc.say_migrate2  = и я сделаю это сам: поставлю порты, проверю что встали бинарником,
mpc.say_migrate3  = сниму из brew и подчищу осиротевшее.
mpc.b_required    = Флаг -b обязателен: binary-only, прерывается вместо сборки.
mpc.point_of_it   = Смысл переезда: MacPorts живёт в %s со своими копиями
mpc.point_of_it2  = библиотек, не зависит от системных и поддерживает платформу годами.
mpc.none_ready    = готовых к переезду портов нет
mpc.tree_behind   = Дерево портов отстало от сервера: %s
mpc.tree_behind2  = Архивы собраны, но под другие версии. Сначала sudo port selfupdate.
mpc.urgent        = срочно (brew уже компилирует, а порта ещё нет): %s

# -------------------------------------- MacPorts: пересборка списка слежения -
mpw.rebuilt       = список пересобран из brew leaves: %s шт. —
mpw.locked_out    = переехать не могут: %s — их требуют cask'и
mpw.no_port_name  = имя порта не подобралось: %s
mpw.naming_note   = (brew и MacPorts зовут пакеты по-разному — libpq это postgresql18;
mpw.naming_note2  = если такой нужен, впиши строкой в MACPORTS_WATCH вручную)

# ------------------------------------------------ предполётная проверка brew -
pf.no_cache       = кэш brew не найден — предполётная проверка пропущена (нужен brew update)
pf.cache_unread   = не смог прочитать кэш brew: %s
pf.nothing        = brew: обновлять нечего
pf.pending        = ждут обновления: %s
pf.from_source    = из исходников: %s
pf.heavy          = ← ТЯЖЁЛЫЙ ТУЛЧЕЙН: %s
pf.will_pour      = разольётся бутылкой
pf.held           = закреплены и не тронутся: %s
pf.dont_upgrade   = Не запускай brew upgrade целиком.
pf.heavy_note1    = Тяжёлый тулчейн собирается часами и берёт все ядра — бутстрап
pf.heavy_note2    = rust и сборка LLVM на HOMEBREW_MAKE_JOBS не смотрят.
pf.heavy_note3    = Закрепи виновника:
pf.heavy_cmd      = brew pin <формула>
pf.minutes        = Сборки из исходников есть, но тяжёлого тулчейна нет — это минуты.

# ------------------------------------------------- кто держит формулы в brew -
ow.none_left      = формул в brew не осталось — держать нечего
ow.info_unread    = не смог прочитать brew info: %s
ow.holder_formula = формула %s
ow.holder_cask    = cask %s
ow.installed      = формул установлено: %s
ow.no_holders     = держать их некому — можно сносить:
ow.cask_only      = %s держит только cask: %s
ow.cask_only_note = формулы на него не ссылаются; в рантайме cask берёт свой интерпретатор
ow.pulls          = тянет за собой: %s
ow.no_bottle      = без бутылки под нашу платформу, при переустановке соберётся из исходников:
ow.order_matters  = снести так — порядок важен, между командами не запускай brew upgrade:
ow.will_return    = вернётся при brew upgrade --cask %s — тогда снова закрепи
ow.risky          = без бутылки и НЕ закреплены — следующий brew upgrade будет их собирать:
ow.all_safe       = всё закреплено или имеет бутылку — внезапных сборок не будет

# ------------------------------------------------------------- bootstrap -----
bs.brew_empty     = в Homebrew ничего не установлено — переезжать нечего
bs.inventory      = Homebrew: формул %s, cask'ов %s
bs.bottle_tag     = , bottle_tag %s
bs.cache_unread   = кэш brew не прочитан — про бутылки сказать нечего, сделай brew update
bs.probing        = проверяю %s формул в MacPorts...
bs.bottled        = бутылка есть
bs.not_bottled    = БЕЗ БУТЫЛКИ — соберётся из исходников
bs.only_casks     = формул в brew нет — переезжать нечего, остались только cask'и
bs.route1         = 1. Вендорский бинарник — %s
bs.route1_note    = этот скрипт умеет их ставить сам, компилятор и root не нужны
bs.after_check    = ← после проверки
bs.route2         = 2. MacPorts — %s, архив под эту платформу есть
bs.route2_note    = строго с -b: без архива порт не станет компилироваться, а просто пропустится
bs.route3         = 3. Пока остаётся в brew — %s
bs.why_no_port    = в MacPorts порта нет
bs.why_no_archive = порт есть, но архива под эту платформу нет
bs.why_stale      = архив есть, но не той версии, которую хочет дерево портов
bs.why_no_mp      = MacPorts не установлен
bs.nobody_holds   = ← не держит никто, можно сносить
bs.risky1         = Эти соберутся из исходников на первом же brew upgrade.
bs.risky2         = Закрепи их, пока не нашлась замена:
bs.cask_pulls     = cask'и, тянущие формулы — их переезд упирается в cask, а не в формулу:
bs.order1         = Порядок: сначала пункт 1, потом 2, и только то, что осталось — пункт 3.
bs.order2         = После каждого шага проверяй, что инструмент работает, и только потом сноси из brew.
