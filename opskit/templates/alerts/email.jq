"From: \($from)\r\nTo: \($to)\r\nSubject: [\(.severity | ascii_upcase)] \(.client): \(.what | gsub("[\r\n]"; " ") | .[0:120])\r\nDate: \(.date)\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n"
+ text
+ "\r\n\r\nHost: \(.host)\r\nTime (UTC): \(.at)\r\n"
