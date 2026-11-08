import Foundation

/// English interface text, keyed by the regular Russian variant written at the call site.
/// Each line: Russian regular ⟩ English lowercase style ⟩ English regular. Spaces at the ends are significant.
public enum English {
    public static let table: [String: (low: String, regular: String)] = {
        var result: [String: (low: String, regular: String)] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.components(separatedBy: "⟩")
            guard parts.count == 3 else { continue }
            result[parts[0]] = (parts[1], parts[2])
        }
        return result
    }()
    static let source = """
Ищем браузеры на этом Mac⟩looking for browsers on this Mac⟩Looking for browsers on this Mac
Доступные профили не найдены. Можно выбрать папку профиля или файл экспорта⟩no accessible profiles found. choose a profile folder or an export file⟩No accessible profiles found. Choose a profile folder or an export file
Выбрать папку профиля…⟩choose a profile folder…⟩Choose a profile folder…
Выберите папку профиля браузера или папку с его профилями⟩choose a browser profile folder or the folder containing its profiles⟩Choose a browser profile folder or the folder containing its profiles
Профили в этой папке не найдены⟩no profiles found in this folder⟩No profiles found in this folder
macOS ограничивает доступ к файлам Safari. Экспортируйте данные в Safari: «Файл», «Экспортировать», «Данные браузера в файл», затем выберите архив здесь⟩macOS restricts access to Safari files. export from Safari using File, Export, Browsing Data to File, then select the archive here⟩macOS restricts access to Safari files. Export from Safari using File, Export, Browsing Data to File, then select the archive here
Откуда⟩from⟩From
Что перенести⟩what to import⟩What to import
Входы на сайты и пароли не переносятся. Исходный браузер не изменяется⟩sign-ins and passwords are not imported. the original browser is not changed⟩Sign-ins and passwords are not imported. The original browser is not changed
Закладки и избранное⟩bookmarks and favorites⟩Bookmarks and favorites
Перенести⟩import⟩Import
Из файла экспорта…⟩from an export file…⟩From an export file…
Готово: ⟩done: ⟩Done:\u{20}
История: ⟩history: ⟩History:\u{20}
Закладки: ⟩bookmarks: ⟩Bookmarks:\u{20}
Выберите архив экспорта Safari, его папку или HTML-файл с закладками⟩choose a Safari export archive, its folder, or an HTML bookmarks file⟩Choose a Safari export archive, its folder, or an HTML bookmarks file
В файле нет закладок или истории в известном формате⟩the file contains no bookmarks or history in a recognized format⟩The file contains no bookmarks or history in a recognized format
: нет доступа к файлу⟩: no access to the file⟩: no access to the file
: файл не прочитан, возможно, браузер сменил формат⟩: could not read the file, the browser may have changed its format⟩: could not read the file, the browser may have changed its format
Доступна mica ⟩mica is available: ⟩mica is available:\u{20}
Образ будет проверен по SHA-256 и открыт в Finder. Установку вы завершите сами⟩the disk image will be checked against its SHA-256 checksum and opened in Finder. you will finish installation yourself⟩The disk image will be checked against its SHA-256 checksum and opened in Finder. You will finish installation yourself
Позже⟩later⟩Later
Не предлагать эту версию⟩skip this version⟩Skip this version
Не предлагать никогда⟩never offer updates⟩Never offer updates
Сохраните проверенный образ mica⟩save the verified mica disk image⟩Save the verified mica disk image
Контрольная сумма не совпала. Образ не открыт⟩the checksum did not match. the disk image was not opened⟩The checksum did not match. The disk image was not opened
Не удалось включить проверку Gatekeeper. Образ не открыт⟩could not enable Gatekeeper verification. the disk image was not opened⟩Could not enable Gatekeeper verification. The disk image was not opened
Не удалось скачать или открыть образ. Попробуйте позже⟩could not download or open the disk image. try again later⟩Could not download or open the disk image. Try again later
Обновление не установлено⟩update not installed⟩Update not installed
Понятно⟩OK⟩OK
Установить mica в «Программы»?⟩install mica in Applications?⟩Install mica in Applications?
Выберите папку «Программы» для установки⟩choose the Applications folder to install⟩Choose the Applications folder to install
Обновить mica в «Программах»?⟩update mica in Applications?⟩Update mica in Applications?
Установлена версия ⟩installed version: ⟩Installed version:\u{20}
, на образе версия ⟩, disk image version: ⟩, disk image version:\u{20}
Продолжить⟩continue⟩Continue
Выберите папку «Программы»⟩choose the Applications folder⟩Choose the Applications folder
Выбрать⟩choose⟩Choose
mica установлена⟩mica is installed⟩mica is installed
Откройте mica из папки «Программы»⟩open mica from the Applications folder⟩Open mica from the Applications folder
Не удалось установить mica⟩could not install mica⟩Could not install mica
Проверьте доступ к папке «Программы» и установленную версию⟩check access to the Applications folder and the installed version⟩Check access to the Applications folder and the installed version
Перенос данных⟩import data⟩Import data
Всё уже на месте⟩everything is in place⟩Everything is in place
История и закладки из другого браузера. Шаг можно пропустить⟩history and bookmarks from another browser. you can skip this step⟩History and bookmarks from another browser. You can skip this step
Проверять обновления каждый день⟩check for updates daily⟩Check for updates daily
Закрыть окно и отменить загрузки?⟩close the window and cancel downloads?⟩Close the window and cancel downloads?
Незавершённые загрузки этого окна будут отменены⟩unfinished downloads in this window will be cancelled⟩Unfinished downloads in this window will be cancelled
Отмена⟩cancel⟩Cancel
Закрыть⟩close⟩Close
Завершить mica и отменить загрузки?⟩quit mica and cancel downloads?⟩Quit mica and cancel downloads?
Незавершённые загрузки будут отменены⟩unfinished downloads will be cancelled⟩Unfinished downloads will be cancelled
Завершить⟩quit⟩Quit
О mica⟩about mica⟩About mica
Настройки…⟩settings…⟩Settings…
Службы⟩services⟩Services
Скрыть mica⟩hide mica⟩Hide mica
Завершить mica⟩quit mica⟩Quit mica
Файл⟩file⟩File
Новая вкладка⟩new tab⟩New Tab
Новое окно⟩new window⟩New Window
Новое окно инкогнито⟩new incognito window⟩New Incognito Window
Закрыть вкладку⟩close tab⟩Close Tab
Восстановить вкладку⟩reopen closed tab⟩Reopen Closed Tab
Печать…⟩print…⟩Print…
Правка⟩edit⟩Edit
Найти на странице⟩find on page⟩Find on Page
Вид⟩view⟩View
Увеличить⟩zoom in⟩Zoom In
Уменьшить⟩zoom out⟩Zoom Out
Исходный масштаб⟩actual size⟩Actual Size
Показать или скрыть боковую панель⟩show or hide sidebar⟩Show or Hide Sidebar
Настроить панель инструментов…⟩customize toolbar…⟩Customize Toolbar…
Полноэкранный режим⟩full screen⟩Full Screen
Переход⟩go⟩Go
Адресная строка⟩address bar⟩Address Bar
Назад⟩back⟩Back
Вперёд⟩forward⟩Forward
Перезагрузить⟩reload⟩Reload
Следующая вкладка⟩next tab⟩Next Tab
Предыдущая вкладка⟩previous tab⟩Previous Tab
Библиотека⟩library⟩Library
Закладка для страницы⟩bookmark this page⟩Bookmark This Page
История⟩history⟩History
Загрузки⟩downloads⟩Downloads
Расширения⟩extensions⟩Extensions
Окно⟩window⟩Window
Свернуть⟩minimize⟩Minimize
В этой сборке нет набора иконок⟩this build has no icon set⟩This build has no icon set
Другой цвет⟩other color⟩Other color
Акцентный цвет⟩accent color⟩Accent color
Инкогнито⟩incognito⟩Incognito
Этот адрес или протокол не поддерживается⟩this address or protocol is not supported⟩This address or protocol is not supported
Этот протокол не поддерживается: ⟩this protocol is not supported: ⟩This protocol is not supported: 
Открыть другое приложение?⟩open another app?⟩Open another app?
Открыть⟩open⟩Open
Процесс страницы завершён системой. Восстановите страницу; несохранённые формы могут быть потеряны.⟩the system ended the page process. restore the page; unsaved forms may be lost.⟩The system ended the page process. Restore the page; unsaved forms may be lost.
Вход на сайт⟩sign in to site⟩Sign In to Site
Имя пользователя⟩user name⟩User name
Пароль⟩password⟩Password
Войти⟩sign in⟩Sign In
Камера⟩camera⟩Camera
Микрофон⟩microphone⟩Microphone
Сайт запрашивает доступ для записи или звонка. macOS отдельно проверит системное разрешение.⟩the site asks for access to record or call. macOS checks its own permission separately.⟩The site asks for access to record or call. macOS checks its own permission separately.
Запрос из встроенного фрейма на ⟩request from an embedded frame on ⟩Request from an embedded frame on 
Запретить⟩deny⟩Deny
Разрешить один раз⟩allow once⟩Allow Once
Разрешить для сайта⟩allow for this site⟩Allow for This Site
Доступ запрещён macOS. Разрешения можно изменить в системных настройках конфиденциальности.⟩macOS denied access. you can change it in the system privacy settings.⟩macOS denied access. You can change it in the system privacy settings.
Слева от адреса⟩left of the address⟩Left of the address
Справа от адреса⟩right of the address⟩Right of the address
В боковой панели⟩in the sidebar⟩In the sidebar
Не показывается⟩not shown⟩Not shown
Убрать⟩remove⟩Remove
Перетащите или откройте меню действий⟩drag it or open the actions menu⟩Drag it or open the actions menu
Перетащите кнопки на панель⟩drag buttons onto the toolbar⟩Drag buttons onto the toolbar
В шапку по обе стороны от адреса. Чтобы убрать кнопку, верните её сюда.⟩to either side of the address. to remove a button, drag it back here.⟩To either side of the address. To remove a button, drag it back here.
В шапку по обе стороны от адреса или вниз боковой панели. Чтобы убрать кнопку, верните её сюда.⟩to either side of the address or to the bottom of the sidebar. to remove a button, drag it back here.⟩To either side of the address or to the bottom of the sidebar. To remove a button, drag it back here.
Длина адресной строки⟩address bar length⟩Address bar length
Вернуть как было⟩restore defaults⟩Restore Defaults
Иконка приложения⟩app icon⟩App Icon
Иконка меняется в Доке и переключателе приложений. Если mica закреплена в Доке, иконка остаётся и после выхода. В Finder и Launchpad остаётся стандартная.⟩the icon changes in the Dock and the app switcher. if mica is kept in the Dock, the icon stays after quitting too. Finder and Launchpad keep the standard one.⟩The icon changes in the Dock and the app switcher. If mica is kept in the Dock, the icon stays after quitting too. Finder and Launchpad keep the standard one.
Готово⟩done⟩Done
Можно добавить⟩not on the toolbar⟩Not on the toolbar
Очистить⟩clear⟩Clear
Сохранить загрузку⟩save download⟩Save Download
Заменить существующий файл?⟩replace the existing file?⟩Replace the existing file?
Заменить⟩replace⟩Replace
Открыть загруженный файл?⟩open the downloaded file?⟩Open the downloaded file?
Обязательные API недоступны в этом WebKit: ⟩required APIs are unavailable in this WebKit: ⟩Required APIs are unavailable in this WebKit: 
WebKit не предоставляет: ⟩WebKit does not provide: ⟩WebKit does not provide: 
Файлы изменены. Импортируйте расширение заново и проверьте разрешения.⟩the files have changed. import the extension again and review its permissions.⟩The files have changed. Import the extension again and review its permissions.
Удалить расширение?⟩remove the extension?⟩Remove the extension?
Удалить⟩remove⟩Remove
Выберите папку с manifest.json или пакет ZIP/XPI. Код запускается только после проверки разрешений.⟩choose a folder with manifest.json or a ZIP/XPI package. code runs only after you review permissions.⟩Choose a folder with manifest.json or a ZIP/XPI package. Code runs only after you review permissions.
manifest.json должен находиться в корне пакета⟩manifest.json must be at the root of the package⟩manifest.json must be at the root of the package
Не поддерживаются обязательные разрешения: ⟩required permissions are not supported: ⟩Required permissions are not supported: 
Сайты: ⟩sites: ⟩Sites: 
Источник: Chrome Web Store. Подпись CRX3 разработчика проверена, ключ соответствует ID расширения. API Chrome доступны в объёме WebKit.⟩source: Chrome Web Store. the developer's CRX3 signature is verified and the key matches the extension ID. Chrome APIs are available as far as WebKit supports them.⟩Source: Chrome Web Store. The developer's CRX3 signature is verified and the key matches the extension ID. Chrome APIs are available as far as WebKit supports them.
Источник: Firefox Add-ons. SHA-256 пакета совпал с ответом каталога.⟩source: Firefox Add-ons. the package SHA-256 matches the catalog response.⟩Source: Firefox Add-ons. The package SHA-256 matches the catalog response.
Источник: файл с диска. Подпись издателя не проверена. SHA-256 фиксирует целостность локальной копии.⟩source: a file on disk. the publisher signature is not verified. SHA-256 records the integrity of the local copy.⟩Source: a file on disk. The publisher signature is not verified. SHA-256 records the integrity of the local copy.
Окна инкогнито недоступны. Совместимость требует проверки.⟩incognito windows are not available to it. compatibility needs checking.⟩Incognito windows are not available to it. Compatibility needs checking.
Установить без доступа к сайтам⟩install without site access⟩Install Without Site Access
Установить с указанным доступом⟩install with requested access⟩Install with Requested Access
Расширение не установлено: ⟩extension not installed: ⟩Extension not installed: 
Введите название для поиска в Firefox Add-ons⟩type a name to search Firefox Add-ons⟩Type a name to search Firefox Add-ons
Поиск в Firefox Add-ons⟩searching Firefox Add-ons⟩Searching Firefox Add-ons
Ничего не найдено⟩nothing found⟩Nothing found
Источник: Firefox Add-ons. Совместимость каждого расширения не гарантируется.⟩source: Firefox Add-ons. compatibility of each extension is not guaranteed.⟩Source: Firefox Add-ons. Compatibility of each extension is not guaranteed.
Каталог недоступен: ⟩catalog unavailable: ⟩Catalog unavailable: 
У этого расширения нет пакета для прямой установки⟩this extension has no package for direct install⟩This extension has no package for direct install
Контрольная сумма пакета не совпала с AMO, установка отменена⟩the package checksum does not match AMO, install cancelled⟩The package checksum does not match AMO, install cancelled
Не удалось установить: ⟩could not install: ⟩Could not install: 
Нужна ссылка на страницу расширения в Chrome Web Store или его ID из 32 букв⟩paste a Chrome Web Store extension page link or its 32-letter ID⟩Paste a Chrome Web Store extension page link or its 32-letter ID
Загрузка и проверка подписи…⟩downloading and checking the signature…⟩Downloading and checking the signature…
Магазин не отдал пакет: расширение не найдено, снято с публикации или недоступно для загрузки⟩the store returned no package: the extension was not found, was unpublished or cannot be downloaded⟩The store returned no package: the extension was not found, was unpublished or cannot be downloaded
Разрешить чтение и изменение страниц на ⟩allow reading and changing pages on ⟩Allow reading and changing pages on 
Разрешить⟩allow⟩Allow
Один раз⟩once⟩Once
Закладки⟩bookmarks⟩Bookmarks
Закрыть панель⟩close panel⟩Close Panel
Поиск⟩search⟩Search
История окна инкогнито не записывается⟩incognito history is not recorded⟩Incognito history is not recorded
История пока пуста⟩history is empty⟩History is empty
Добавьте закладку через ⌘D⟩add a bookmark with ⌘D⟩Add a bookmark with ⌘D
Очистить историю…⟩clear history…⟩Clear History…
Очистить историю?⟩clear history?⟩Clear history?
Данные сайтов и закладки сохранятся⟩site data and bookmarks are kept⟩Site data and bookmarks are kept
Открыть в новой вкладке⟩open in new tab⟩Open in New Tab
Копировать адрес⟩copy address⟩Copy Address
Загрузки появятся здесь⟩downloads appear here⟩Downloads appear here
Выбор файла⟩choosing a file⟩Choosing a file
Отменить⟩cancel⟩Cancel
Показать в Finder⟩show in Finder⟩Show in Finder
Повторить⟩retry⟩Retry
Возобновить⟩resume⟩Resume
Сохранено⟩saved⟩Saved
Отменено⟩cancelled⟩Cancelled
Ошибка загрузки⟩download failed⟩Download failed
Ожидает выбора места⟩waiting for a location⟩Waiting for a location
Расширения работают только в обычных окнах⟩extensions work only in regular windows⟩Extensions work only in regular windows
Найти в Firefox Add-ons⟩search Firefox Add-ons⟩Search Firefox Add-ons
Установленные⟩installed⟩Installed
С диска…⟩from disk…⟩From Disk…
Пока ничего не установлено⟩nothing installed yet⟩Nothing installed yet
Каталог⟩catalog⟩Catalog
Каталог Firefox Add-ons загружается только по вашему поиску⟩the Firefox Add-ons catalog loads only when you search⟩The Firefox Add-ons catalog loads only when you search
Открыто в текущей вкладке⟩open in the current tab⟩Open in the current tab
Обновить⟩update⟩Update
Установить⟩install⟩Install
Ссылка на расширение или его ID⟩extension link or ID⟩Extension link or ID
Return устанавливает. mica скачивает тот же пакет, что получает Chrome, проверяет подпись разработчика и показывает права до запуска. API Chrome работают в объёме WebKit.⟩Return installs. mica downloads the same package Chrome gets, checks the developer signature and shows permissions before anything runs. Chrome APIs work as far as WebKit supports them.⟩Return installs. mica downloads the same package Chrome gets, checks the developer signature and shows permissions before anything runs. Chrome APIs work as far as WebKit supports them.
Открыть магазин⟩open the store⟩Open the Store
Открыть ⟩open ⟩Open 
Настройки расширения⟩extension settings⟩Extension Settings
Разрешить текущий сайт⟩allow current site⟩Allow Current Site
Отозвать доступ к сайтам⟩revoke site access⟩Revoke Site Access
Обновить с диска⟩update from disk⟩Update from Disk
Действия⟩actions⟩Actions
доступ не выдан⟩no access granted⟩no access granted
Заявленные права: ⟩declared permissions: ⟩Declared permissions: 
Загрузка и проверка…⟩downloading and checking…⟩Downloading and checking…
Установлено⟩installed⟩Installed
Обновить до ⟩update to ⟩Update to 
Страница и лицензия⟩page and license⟩Page and License
Пространство⟩space⟩Space
Оформление⟩appearance⟩Appearance
Начальная страница⟩start page⟩Start Page
Поиск и защита⟩search and protection⟩Search and Protection
Сессия и память⟩session and memory⟩Session and Memory
Разрешения сайтов⟩site permissions⟩Site Permissions
Адрес не добавлен⟩address not added⟩Address not added
Введённый адрес «⟩the address “⟩The address “
» ещё не сохранён в списке.⟩” is not saved in the list yet.⟩” is not saved in the list yet.
Продолжить редактирование⟩keep editing⟩Keep Editing
Закрыть без сохранения⟩close without saving⟩Close Without Saving
Настройки⟩settings⟩Settings
Поисковые запросы отправляются выбранному поисковику. Каталог расширений обращается к Firefox Add-ons только при поиске и установке, к Chrome Web Store только при установке. Сайты, расширения и macOS могут выполнять собственные сетевые запросы.⟩searches go to the search engine you chose. the extension catalog contacts Firefox Add-ons only when you search or install, and Chrome Web Store only when you install. sites, extensions and macOS can make their own network requests.⟩Searches go to the search engine you chose. The extension catalog contacts Firefox Add-ons only when you search or install, and Chrome Web Store only when you install. Sites, extensions and macOS can make their own network requests.
Локальный браузер на системном WebKit⟩a local browser on the system WebKit⟩A local browser on the system WebKit
Без собственной телеметрии и аналитики⟩no telemetry or analytics of its own⟩No telemetry or analytics of its own
Знакомство с mica⟩mica introduction⟩mica Introduction
Пройти первые шаги ещё раз⟩go through the first steps again⟩Go through the first steps again
Пройти⟩start⟩Start
Раскладка⟩layout⟩Layout
При ширине окна меньше 760 pt вкладки временно переходят наверх. В свёрнутой боковой панели остаются иконки сайтов, ⌃⌘S.⟩in windows narrower than 760 pt tabs move to the top for a while. a collapsed sidebar keeps site icons, ⌃⌘S.⟩In windows narrower than 760 pt tabs move to the top for a while. A collapsed sidebar keeps site icons, ⌃⌘S.
Вкладки⟩tabs⟩Tabs
Свернуть боковую панель до иконок⟩collapse sidebar to icons⟩Collapse sidebar to icons
Панель инструментов⟩toolbar⟩Toolbar
Кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. То же меню есть по правому клику на шапке.⟩you arrange buttons by dragging them right in the window: into the top bar, to the bottom of the sidebar or back to the set. the same command is in the top bar's context menu.⟩You arrange buttons by dragging them right in the window: into the top bar, to the bottom of the sidebar or back to the set. The same command is in the top bar's context menu.
Кнопки и адресная строка⟩buttons and address bar⟩Buttons and address bar
Порядок, сторона и длина строки⟩order, side and bar length⟩Order, side and bar length
Настроить⟩customize⟩Customize
Материал оболочки⟩window material⟩Window Material
Размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. Системные «Уменьшить прозрачность» и «Увеличить контраст» имеют приоритет.⟩blur and transparency apply only to the window frame, pages stay opaque. the system settings reduce transparency and increase contrast take priority.⟩Blur and transparency apply only to the window frame, pages stay opaque. The system settings Reduce Transparency and Increase Contrast take priority.
Матовое стекло⟩frosted glass⟩Frosted glass
Прозрачность⟩transparency⟩Transparency
Иконка в Доке⟩Dock icon⟩Dock Icon
Меняется иконка в Доке и переключателе приложений, пока mica запущена. После выхода Док и Finder показывают иконку сборки: приложение в песочнице не может изменить собственный bundle.⟩the icon changes in the Dock and the app switcher while mica runs. after quitting, the Dock and Finder show the build icon: a sandboxed app cannot change its own bundle.⟩The icon changes in the Dock and the app switcher while mica runs. After quitting, the Dock and Finder show the build icon: a sandboxed app cannot change its own bundle.
Язык и текст⟩language and text⟩Language and Text
Язык меняет только интерфейс mica. Страницы сайтов, адреса и ваши данные не переводятся.⟩the language changes only the mica interface. web pages, addresses and your data are not translated.⟩The language changes only the mica interface. Web pages, addresses and your data are not translated.
Язык⟩language⟩Language
Текст интерфейса⟩interface text⟩Interface text
Названия брендов и сайтов сохраняют написание⟩brand and site names keep their spelling⟩Brand and site names keep their spelling
Тема⟩theme⟩Theme
Акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. Страницы сайтов не меняются.⟩the accent tints the window frame, switches, main buttons and the loading indicator. web pages do not change.⟩The accent tints the window frame, switches, main buttons and the loading indicator. Web pages do not change.
Основа⟩base⟩Base
Как в системе⟩match system⟩Match System
Светлая⟩light⟩Light
Тёмная⟩dark⟩Dark
Основа темы⟩theme base⟩Theme base
Акцент⟩accent⟩Accent
Цвет оболочки⟩frame tint⟩Frame tint
Насколько акцент окрашивает фон окна⟩how strongly the accent tints the window background⟩How strongly the accent tints the window background
Слева⟩left⟩Left
Сверху⟩top⟩Top
Справа⟩right⟩Right
Системная⟩system⟩System
Кастом⟩custom⟩Custom
Имя⟩name⟩Name
Для приветствия на начальной странице⟩for the start page greeting⟩For the start page greeting
Как к вам обращаться⟩what should mica call you⟩What should mica call you
Не обращаться по имени⟩don't use my name⟩Don't use my name
Поисковик⟩search engine⟩Search engine
Запрос из адресной строки уходит только выбранному поисковику⟩a query from the address bar goes only to the search engine you chose⟩A query from the address bar goes only to the search engine you chose
Блокировка⟩blocking⟩Blocking
Блокировать рекламу и трекеры⟩block ads and trackers⟩Block ads and trackers
Только сторонние запросы, без косметических фильтров⟩third-party requests only, no cosmetic filters⟩Third-party requests only, no cosmetic filters
Сайты без блокировки⟩sites without blocking⟩Sites Without Blocking
Вернуть блокировку⟩block again⟩Block Again
Данные⟩data⟩Data
История и данные сайтов⟩history and site data⟩History and site data
Cookie, кэш и локальное хранилище обычных окон⟩cookies, cache and local storage of regular windows⟩Cookies, cache and local storage of regular windows
Очистить…⟩clear…⟩Clear…
Очистить историю и данные сайтов?⟩clear history and site data?⟩Clear history and site data?
Вы выйдете из аккаунтов на сайтах. Закладки сохранятся.⟩you will be signed out of sites. bookmarks are kept.⟩You will be signed out of sites. Bookmarks are kept.
При запуске⟩on launch⟩On Launch
Это касается только запуска. Открытые вами вкладки остаются живыми, включая фоновые. Несохранённые формы после сбоя не восстанавливаются.⟩this applies only to launch. tabs you open stay live, background ones included. unsaved forms are not restored after a crash.⟩This applies only to launch. Tabs you open stay live, background ones included. Unsaved forms are not restored after a crash.
Восстанавливать окна и вкладки⟩restore windows and tabs⟩Restore windows and tabs
Загружать сохранённые вкладки при выборе⟩load restored tabs when selected⟩Load restored tabs when selected
Всегда загружать при запуске⟩always load on launch⟩Always Load on Launch
Например, почта или мессенджер, которым нужны уведомления сразу⟩for example mail or a messenger that needs notifications right away⟩For example mail or a messenger that needs notifications right away
Память⟩memory⟩Memory
Публичный WebKit не позволяет надёжно определить звонки, формы и WebSocket, поэтому mica не выгружает живые вкладки. Автоматического таймера выгрузки нет.⟩public WebKit cannot reliably detect calls, forms and WebSockets, so mica does not unload live tabs. there is no automatic unload timer.⟩Public WebKit cannot reliably detect calls, forms and WebSockets, so mica does not unload live tabs. There is no automatic unload timer.
Выгрузка живых вкладок⟩unloading live tabs⟩Unloading live tabs
Выключена⟩off⟩Off
Системный доступ меняется в настройках конфиденциальности macOS⟩system access is changed in macOS privacy settings⟩System access is changed in macOS privacy settings
Системные настройки⟩system settings⟩System Settings
Решения для сайтов⟩site decisions⟩Site Decisions
Решения окон инкогнито существуют только внутри окна. Геолокация и веб-уведомления недоступны для управления через публичный API этой версии.⟩incognito decisions live only inside that window. location and web notifications cannot be managed through the public API of this version.⟩Incognito decisions live only inside that window. Location and web notifications cannot be managed through the public API of this version.
Сайты пока ничего не запрашивали⟩no site has asked yet⟩No site has asked yet
Спрашивать⟩ask⟩Ask
Разрешено⟩allowed⟩Allowed
Запрещено⟩denied⟩Denied
Ограничено системой⟩restricted by the system⟩Restricted by the system
Ещё не запрашивалось⟩not requested yet⟩Not requested yet
Добавить⟩add⟩Add
Нужен домен без пути, например mail.example.com⟩a domain without a path is needed, for example mail.example.com⟩A domain without a path is needed, for example mail.example.com
Удалить ⟩remove ⟩Remove 
Список Peter Lowe⟩Peter Lowe list⟩Peter Lowe list
 доменов. ⟩ domains. ⟩ domains. 
Обновление только по кнопке, запрос к pgl.yoyo.org⟩updates only on request, from pgl.yoyo.org⟩Updates only on request, from pgl.yoyo.org
Обновление…⟩updating…⟩Updating…
Приветствие⟩greeting⟩Greeting
С именем над поиском появляется приветствие, без имени остаётся знак mica. Имя хранится только на этом Mac.⟩with a name, a greeting appears above search; without one the mica wordmark stays. the name is kept only on this Mac.⟩With a name, a greeting appears above search; without one the mica wordmark stays. The name is kept only on this Mac.
Что показывать⟩what to show⟩What to Show
Стрелки меняют порядок разделов. Частые сайты считаются по истории обычных окон и не показываются в окне инкогнито.⟩the arrows reorder sections. frequent sites come from regular window history and are not shown in incognito.⟩The arrows reorder sections. Frequent sites come from regular window history and are not shown in incognito.
Приветствие или знак mica⟩greeting or mica wordmark⟩Greeting or mica wordmark
Выше⟩up⟩Up
Ниже⟩down⟩Down
Сайтов в разделе⟩sites per section⟩Sites per section
Для частых сайтов и закладок⟩for frequent sites and bookmarks⟩For frequent sites and bookmarks
Свои сайты⟩your sites⟩Your Sites
На начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их.⟩on the start page you can drag tiles; the context menu edits and removes them.⟩On the start page you can drag tiles; the context menu edits and removes them.
Скрытые из частых⟩hidden from frequent⟩Hidden from Frequent
Вернуть⟩restore⟩Restore
Адрес сайта⟩site address⟩Site address
Нужен адрес сайта, а не поисковый запрос⟩a site address is needed, not a search query⟩A site address is needed, not a search query
Шаг ⟩step ⟩Step 
Начать⟩start⟩Start
Дальше⟩next⟩Next
Привет, это mica⟩hi, this is mica⟩Hi, this is mica
Ваше пространство⟩your space⟩Your space
Цвет и иконка⟩color and icon⟩Color and icon
Спокойнее с первого запуска⟩calmer from the first launch⟩Calmer from the first launch
Работа остаётся с вами⟩your work stays with you⟩Your work stays with you
Язык, имя и стиль текста. Всё можно поменять позже в настройках⟩language, name and text style. you can change all of it later in settings⟩Language, name and text style. You can change all of it later in settings
Изменения видны сразу⟩changes show right away⟩Changes show right away
Тема окна, акцент и иконка mica в Доке⟩window theme, accent and the mica icon in the Dock⟩Window theme, accent and the mica icon in the Dock
Поиск, блокировка и разрешения⟩search, blocking and permissions⟩Search, blocking and permissions
Вкладки, сессия и клавиши⟩tabs, session and shortcuts⟩Tabs, session and shortcuts
Матовое стекло оболочки⟩frosted window frame⟩Frosted window frame
Локальные правила WebKit для известных сторонних доменов⟩local WebKit rules for known third-party domains⟩Local WebKit rules for known third-party domains
Камера и микрофон запрашиваются только по запросу сайта, с его адресом в вопросе⟩camera and microphone are requested only when a site asks, with its address in the prompt⟩Camera and microphone are requested only when a site asks, with its address in the prompt
Окна инкогнито не сохраняют историю, cookie и сессию⟩incognito windows keep no history, cookies or session⟩Incognito windows keep no history, cookies or session
Список блокировки обновляется только вручную в настройках⟩the block list updates only manually in settings⟩The block list updates only manually in settings
После открытия вкладки остаются живыми, mica не выгружает страницы по таймеру. После сбоя восстановятся адреса, но не несохранённые формы.⟩once opened, tabs stay live; mica does not unload pages on a timer. after a crash addresses come back, unsaved forms do not.⟩Once opened, tabs stay live; mica does not unload pages on a timer. After a crash addresses come back, unsaved forms do not.
Адрес и поиск⟩address and search⟩Address and search
Окно инкогнито⟩incognito window⟩Incognito Window
Боковая панель⟩sidebar⟩Sidebar
Поиск или адрес⟩search or address⟩Search or address
Начальная страница: ⟩start page: ⟩Start page: 
Предпросмотр оформления и раскладки⟩appearance and layout preview⟩Appearance and layout preview
Не удалось сохранить данные: ⟩could not save data: ⟩Could not save data: 
Сессия повреждена. Исходный файл скопирован в Recovery: ⟩the session is damaged. the original file was copied to Recovery: ⟩The session is damaged. The original file was copied to Recovery: 
Сайты выйдут из аккаунтов. Открытые вкладки сохранятся; формы на страницах могут быть потеряны при перезагрузке.⟩sites will sign you out. open tabs stay; forms on pages may be lost on reload.⟩Sites will sign you out. Open tabs stay; forms on pages may be lost on reload.
Локальные правила готовы⟩local rules ready⟩Local rules ready
Ошибка блокировки: ⟩blocking error: ⟩Blocking error: 
Список не обновлён, предыдущие правила сохранены: ⟩the list was not updated, the previous rules are kept: ⟩The list was not updated, the previous rules are kept: 
Закреплена: ⟩pinned: ⟩Pinned: 
Остановить⟩stop⟩Stop
Развернуть боковую панель⟩expand sidebar⟩Expand Sidebar
Свернуть боковую панель⟩collapse sidebar⟩Collapse Sidebar
Закрыть: ⟩close: ⟩Close: 
Выбрана⟩selected⟩Selected
Ещё не загружена⟩not loaded yet⟩Not loaded yet
Дублировать⟩duplicate⟩Duplicate
Открепить⟩unpin⟩Unpin
Закрепить⟩pin⟩Pin
Открыть в новом окне⟩open in new window⟩Open in New Window
Закрыть остальные⟩close other tabs⟩Close Other Tabs
Сведения о сайте⟩site information⟩Site Information
Адресная строка: ⟩address bar: ⟩Address bar: 
Установить расширение в mica⟩install extension in mica⟩Install Extension in mica
Добавить или удалить закладку⟩add or remove bookmark⟩Add or Remove Bookmark
Адрес или поиск⟩address or search⟩Address or search
Управление расширениями⟩manage extensions⟩Manage Extensions
Поиск: ⟩search: ⟩Search: 
Открыть адрес⟩open address⟩Open address
Перейти к вкладке⟩switch to tab⟩Switch to tab
Соединение HTTPS⟩HTTPS connection⟩HTTPS connection
Защищённое соединение не подтверждено⟩secure connection not confirmed⟩Secure connection not confirmed
Блокировка рекламы на сайте⟩ad blocking on this site⟩Ad blocking on this site
Правила применяются к новым запросам; перезагрузите страницу для полной проверки⟩rules apply to new requests; reload the page to apply them fully⟩Rules apply to new requests; reload the page to apply them fully
Идёт запись с камеры или микрофона⟩the camera or microphone is recording⟩The camera or microphone is recording
Геолокация и веб-уведомления: управляемый доступ недоступен в публичном WebKit этой версии macOS⟩location and web notifications: managed access is not available in the public WebKit of this macOS version⟩Location and web notifications: managed access is not available in the public WebKit of this macOS version
Страница остановлена⟩page stopped⟩Page stopped
Страница недоступна⟩page unavailable⟩Page unavailable
Восстановить⟩restore⟩Restore
История и сессия этого окна не сохраняются. Загруженные файлы остаются на диске.⟩this window's history and session are not saved. downloaded files stay on disk.⟩This window's history and session are not saved. Downloaded files stay on disk.
Поиск в ⟩search ⟩Search 
 или адрес⟩ or enter an address⟩ or enter an address
Вкладка⟩tab⟩Tab
Вкладка ⟩tab ⟩Tab 
Часто открываете⟩frequently visited⟩Frequently Visited
Изменить…⟩edit…⟩Edit…
Переместить левее⟩move left⟩Move Left
Переместить правее⟩move right⟩Move Right
Удалить с начальной страницы⟩remove from start page⟩Remove from Start Page
Закрепить в своих сайтах⟩pin to your sites⟩Pin to Your Sites
Скрыть из частых⟩hide from frequent⟩Hide from Frequent
Настроить начальную страницу…⟩customize start page…⟩Customize Start Page…
Добавить сайт на начальную страницу⟩add a site to the start page⟩Add a site to the start page
Новый сайт⟩new site⟩New Site
Изменить сайт⟩edit site⟩Edit Site
Адрес, например github.com⟩address, for example github.com⟩Address, for example github.com
Название, необязательно⟩name, optional⟩Name, optional
Сохранить⟩save⟩Save
Не найдено⟩not found⟩Not found
Предыдущее совпадение⟩previous match⟩Previous Match
Следующее совпадение⟩next match⟩Next Match
Закрыть поиск⟩close find⟩Close Find
Стандартные⟩standard⟩Standard
Исходная⟩original⟩Original
Кремовая⟩cream⟩Cream
Фиолетовая⟩purple⟩Purple
Голубая⟩blue⟩Blue
Розовая⟩pink⟩Pink
mica — браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь: страница остаётся такой, какой вы её оставили.⟩mica is a browser where tabs don't reload when you come back to them: the page stays exactly as you left it.⟩mica is a browser where tabs don't reload when you come back to them: the page stays exactly as you left it.
Реклама и трекеры блокируются сразу, расширения ставятся из Chrome Web Store и Firefox Add-ons. Собственной телеметрии нет.⟩ads and trackers are blocked out of the box, extensions install from the Chrome Web Store and Firefox Add-ons. mica has no telemetry of its own.⟩Ads and trackers are blocked out of the box, extensions install from the Chrome Web Store and Firefox Add-ons. mica has no telemetry of its own.
Что это: ⟩what is this: ⟩What is this: 
Открытый список доменов рекламных сетей и счётчиков, который Peter Lowe ведёт на pgl.yoyo.org. mica превращает его в правила WebKit, и страницы не могут загрузить с этих доменов баннеры, пиксели и скрипты слежки. Блокируются только запросы к чужим доменам, сам сайт открывается как обычно. Список встроен в приложение и работает без сети. «Обновить» скачивает свежую версию, по расписанию mica в сеть не ходит.⟩an open list of ad network and tracker domains that Peter Lowe maintains at pgl.yoyo.org. mica turns it into WebKit rules, so pages can't load banners, pixels or tracking scripts from those domains. only requests to other domains are blocked, the site itself opens as usual. the list ships with the app and works offline. "update" downloads a fresh copy, mica never fetches it on a schedule.⟩An open list of ad network and tracker domains that Peter Lowe maintains at pgl.yoyo.org. mica turns it into WebKit rules, so pages can't load banners, pixels or tracking scripts from those domains. Only requests to other domains are blocked, the site itself opens as usual. The list ships with the app and works offline. "Update" downloads a fresh copy, mica never fetches it on a schedule.
Красный неон⟩red neon⟩Red neon
Вырезать⟩cut⟩Cut
Копировать⟩copy⟩Copy
Вставить⟩paste⟩Paste
Выбрать всё⟩select all⟩Select All
Боковая панель слева⟩sidebar on the left⟩Sidebar on the Left
Боковая панель справа⟩sidebar on the right⟩Sidebar on the Right
В окне инкогнито частые сайты не показываются⟩frequent sites are not shown in incognito windows⟩Frequent sites are not shown in incognito windows
В шапке четыре места: у краёв окна и рядом с адресом, ещё одно внизу боковой панели. Чтобы убрать кнопку, верните её сюда.⟩the top bar has four places: at the window edges and next to the address, plus one at the bottom of the sidebar. to remove a button, drop it back here.⟩The top bar has four places: at the window edges and next to the address, plus one at the bottom of the sidebar. To remove a button, drop it back here.
В шапке четыре места: у краёв окна и рядом с адресом. Чтобы убрать кнопку, верните её сюда.⟩the top bar has four places: at the window edges and next to the address. to remove a button, drop it back here.⟩The top bar has four places: at the window edges and next to the address. To remove a button, drop it back here.
Версия⟩version⟩Version
Версия ⟩version ⟩Version 
Вкладки сверху⟩tabs on top⟩Tabs on Top
Все настройки⟩all settings⟩All Settings
Глаз показывает и скрывает, стрелки меняют порядок⟩the eye shows and hides, arrows change the order⟩The eye shows and hides, arrows change the order
Здесь будут закладки, ⌘D добавляет страницу⟩bookmarks appear here, ⌘D adds a page⟩Bookmarks appear here, ⌘D adds a page
Знак mica⟩mica wordmark⟩mica Wordmark
Настроить начальную страницу⟩customize start page⟩Customize Start Page
Настройка начальной страницы⟩customizing the start page⟩Customizing the Start Page
Показать⟩show⟩Show
Появятся, когда вы начнёте открывать сайты⟩they appear once you start opening sites⟩They appear once you start opening sites
Пройти знакомство ещё раз⟩take the tour again⟩Take the Tour Again
Скрыто⟩hidden⟩Hidden
Скрыть⟩hide⟩Hide
У левого края⟩at the left edge⟩At the left edge
У правого края⟩at the right edge⟩At the right edge
4 недели⟩4 weeks⟩4 Weeks
Cookie и данные сайтов⟩cookies and site data⟩Cookies and Site Data
Всё время⟩all time⟩All Time
Вчера⟩yesterday⟩Yesterday
Вы выйдете из аккаунтов на сайтах, открытых за этот период⟩you will be signed out of sites opened in this period⟩You will be signed out of sites opened in this period
За этот период записей нет⟩no entries in this period⟩No entries in this period
Знакомство⟩welcome⟩Welcome
История посещений⟩browsing history⟩Browsing History
Камера и микрофон, за всё время: у решений нет даты⟩camera and microphone, for all time: decisions carry no date⟩Camera and microphone, for all time: decisions carry no date
Кэш⟩cache⟩Cache
Неделя⟩week⟩Week
Очистить данные⟩clear data⟩Clear Data
Очистить историю⟩clear history⟩Clear History
Очищаем…⟩clearing…⟩Clearing…
Период⟩period⟩Period
Сегодня⟩today⟩Today
Сессия⟩session⟩Session
Страницы загрузятся заново, это безопасно⟩pages load again from the network, nothing is lost⟩Pages load again from the network, nothing is lost
Сутки⟩24 hours⟩24 Hours
Только обычные окна. Закладки и открытые вкладки останутся⟩regular windows only. bookmarks and open tabs stay⟩Regular windows only. Bookmarks and open tabs stay
Удалить всё с сайта ⟩delete everything from ⟩Delete Everything from 
Час⟩hour⟩Hour
"""
}
