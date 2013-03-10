#! /bin/sh

LANG=C
LC_ALL=C
PATH="$PATH:/usr/local/bin:$HOME/bin:.:.."
export LANG LC_ALL PATH

rm -rf doc
mkdir doc

pod2html --title "Tokyo Cabinet" TokyoCabinet.pod |
sed \
  -e 's/^\t<ul>/\t<li><ul>/' \
  -e 's/^\t<\/ul>/\t<\/ul><\/li>/' \
  -e 's/^<p>&#10;/<p>/' \
  -e 's/^&#10;/<br \/>/g' \
  -e 's/mailto:root@localhost/mailto:info@fallabs.com/' \
  -e 's/ *style="[^"]*"//' \
  -e '/<\/head>/ i<meta http-equiv="content-style-type" content="text/css" />' \
  -e '/<\/head>/ i<style type="text/css">body {\
  padding: 1em 2em;\
  background: #eeeeee none;\
  color: #111111;\
}\
pre {\
  padding: 0.2em 0em;\
  background: #ddddee none;\
  border: 1px solid #cccccc;\
  font-size: 90%;\
}\
dd p {\
  margin: 0.4em 0em 1.0em 0em;\
  padding: 0em;\
}\
</style>' \
> doc/index.html
