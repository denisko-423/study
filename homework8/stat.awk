# Анализатор лога.
#
# Скрипт принимает значения переменных:
# lastrequest - метка последней обработанной записи в логе,
# lastreport - дата/время последнего отчета.
# Результаты обработки выводятся в файл отчета report.
# Для вывода в stdout следует закомментировать
# окончания строк '>>(>) "report"'.
#
# Функция вывода информации в отчет.
function printing(title, array) {
  print "\n" title >> "report"
  for (i in array) {
    if (array[i] == 1) times = "time"; else times = "times"
    printf "%3s %5s: %s\n", array[i], times, i >> "report"
  }
}

BEGIN {
# Индикатор новых записей: 0 - старая запись, 1 - новая.
  new = 0
# При первом запуске метки последней обработанной записи нет,
# поэтому принудительно включаем режим новых записей с первой строки лога.
  if (!lastrequest) new = 1
# Счетчик всех записей в логе.
  allrecords = 0
# Счетчик новых записей в логе.
  newrecords = 0
# Счетчик ошибочных запросов.
  errcount = 0
}

{
# Принимаем только непустые строки.
  if ($0) {
    allrecords++
# Метка записи формируется путем конкатенации ряда полей записи и разделителей.
# По окончании работы скрипта это будет метка последней обработанной записи.
    request = $1 $2 $4 $5 $6 $7 $8 "-" $9 "-" $10
# Если метка текущей записи совпала с последней обработанной,
# то со следующей строки лога начинается анализ.
    if (!new && request == lastrequest) { new = 1; next }
    if (new) {
      newrecords++
# Запросы без GET/POST считаются ошибочными.
      if (substr($6,2) != "GET" && substr($6,2) != "POST") {errcount++; next}
# Ассоциативный массив IP-адресов.
      ipcount[$1]++
# Ассоциативный массив запросов.
      c = split($7, url, "?"); urlcount[url[1]]++
# Ассоциативный массив кодов возврата.
      retcodcount[$9]++
    }
  }
}

END {
# Сортировка ассоциативных массивов по убыванию.
# Найдено в руководствах, понятия не имею, как работает, но работает)
  PROCINFO["sorted_in"] = "@val_num_desc"
  currtime = strftime("%d.%m.%Y %H:%M:%S", systime())
# В файл lastdata записываем метку последней записи и текущее время,
# в следующем отчете это будет время последнего отчета.
  print request " " currtime > "lastdata"
# Собственно вывод в отчет, первый вывод очищает файл.
  print "Current datetime: " currtime > "report"
  print "Last report:      " lastreport >> "report"
  print "All records: " allrecords >> "report"
  print "New records: " newrecords >> "report"
  if (newrecords) {
    printing("IP-addresses", ipcount)
    printing("URLs", urlcount)
    printing("Return codes", retcodcount)
    print "\nBad requests: " errcount >> "report"
  }
}

