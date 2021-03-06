ОБОСНОВАНИЕ МЕТОДИКИ АНАЛИЗА ЛОГА И ПОЯСНЕНИЯ

Я не знаком с промышленными системами анализа логов,
и не представляю, как они это делают.
Поэтому рассмотрел два варианта обработки лога.

Первый вариант - последовательное чтение файла
с запоминанием последней обработанной записи,
чтобы в следующий раз пропустить проанализированные строки.
Недостаток - при очень большом размере файла
большая нагрузка на систему.

Второй вариант - по окончании работы запомнить
количество строк файла, при следующем запуске анализатора
получить текущее количество строк, вычислить количество новых
и каким-либо образом их получить, например с помощью tail.
Недостаток - процессы заполнения и анализа лога асинхронные
и независимые. Пока мы будем вычислять сколько строк
нужно получить, в логе могут появиться новые записи,
что для нагруженной системы очень вероятно,
и мы "промахиваемся" мимо последней обработанной записи.

При разработке анализатора мною принят первый вариант.
Для учебных целей этого достаточно.

Вся работа по анализу проводится awk-скриптом stat.awk.
Скрипт reporter.sh - оболочка для анализатора.

Анализ образца лога access.log показал, что в качестве метки
последней обработанной записи лога лучше всего использовать
совокупность полей записи вплоть до $body_bytes_sent
(возможно это поле избыточно в метке), при меньшем количестве
информации уникальность метки не гарантируется.

Непонятно, что имеется в виду под "ошибками" в задании -
коды возврата 400 и более, или запросы без GET/POST
(специальные или кривые). Принял за ошибки последнее,
подсчитывается количество таких запросов.

Результат прогона скрипта на файле access.log сохранен
в файл-отчет report. Прогон скрипта первый, поэтому поле
"Last report:" не заполнено. При последующих запусках скрипта
здесь будет дата/время предыдущего запуска, которая сохраняется
вместе с меткой последней записи в файле lastdata. Этот файл
необязателен для работы, при его отсутствии анализ лога
начинается с первой записи.

К сожалению, из-за большой загруженности по основной работе
не хватает времени для настраивания cron-а и изучения
темы отправки почты. Это непринципиально, работающий
и отлаженный софт всегда можно "прикрутить" к какому-либо планировщику.

Для демонстрации работы анализатора можно использовать
прилагаемый скрипт-имитатор заполнения лога logger.sh.
Запускать его следует в фоновом режиме:
bash logger.sh &
В скрипте организован бесконечный цикл, по окончании работы
нужно принудительно завершить процесс.

После запуска имитатора при каждом выполнении
bash reporter.sh
будет выводиться свежая аналитика.

