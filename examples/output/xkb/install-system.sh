#!/bin/sh
set -eu

xkb_dir_from=$(dirname "$0")
xkb_dir_to="/usr/share/X11/xkb"
layout="colemak"
description="Colemak"
mods=""

OPTIND=1

while getopts "i:o:l:d:m:" opt; do
  case "$opt" in
    i) xkb_dir_from="$OPTARG";;
    o) xkb_dir_to="$OPTARG";;
    l) layout="$OPTARG";;
    d) description="$OPTARG";;
    m) mods="$OPTARG";;
    *) exit 1;;
  esac
done

if [ -z "$layout" ]; then
  echo "Empty layout"
  exit 2
fi

confirm () {
  # call with a prompt string or use a default
  printf "%s [y/N] " "${1:-Are you sure?}"
  read -r response
  case "${response:-${2:-}}" in
    [yY][eE][sS]|[yY]) true;;
    [nN][oO]|[nN]) false;;
    *) confirm "${1:-}" "${2:-}";;
  esac
}

copy_file () {
  file_from=$1
  file_to=$2

  if [ ! -e "$file_to" ] || grep -qx "// Generated by KLFC .*" "$file_to" || confirm "$file_to already exists. Overwrite?"; then
    cp "$file_from" "$file_to"
  fi
}

add_comment_block () {
  file=$1

  if grep -qx "// End generated by KLFC" "$file"; then
    return
  fi

  echo "" >> "$file"
  echo "// Start generated by KLFC" >> "$file"
  echo "// https://github.com/39aldo39/klfc" >> "$file"
  echo "" >> "$file"
  echo "// End generated by KLFC" >> "$file"
}

add_type () {
  file=$1
  layout=$2

  for group in 0 1 2 3 4; do
    if [ "$group" -eq 0 ]; then
      header="! layout	=	types"
      line="  $layout	=	+$layout"
    else
      header="! layout[$group]	=	types"
      line="  $layout	=	+$layout:$group"
    fi

    if grep -qFx "$line" "$file"; then
      return
    fi

    add_comment_block "$file"
    awk -v header="$header" -v line="$line" '
      /\/\/ End generated by KLFC/ {
        print header
        print line
        print ""
      }
      { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  done
}

add_models () {
  file=$1
  mods=$2
  layout=$3
  header="! model	=	keycodes"

  header_written=false
  for mod in $mods; do
    line="  mod_$mod	=	+$layout($mod)"

    if grep -qFx "$line" "$file"; then
      continue
    fi

    add_comment_block "$file"
    if [ "$header_written" = false ]; then
      awk -v header="$header" -v line="$line" '
        /\/\/ End generated by KLFC/ {
          print header
          print line
        }
        { print }
      ' "$file" > "$file.tmp"
      mv "$file.tmp" "$file"
      header_written=true
    else
      awk -v line="$line" '
        /\/\/ End generated by KLFC/ {
          print line
        }
        { print }
      ' "$file" > "$file.tmp"
      mv "$file.tmp" "$file"
    fi
  done

  if [ "$header_written" = true ]; then
    awk -v header="$header" -v line="$line" '
      /\/\/ End generated by KLFC/ {
        print ""
      }
      { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  fi
}

add_description () {
  file=$1
  layout=$2
  description=$3
  header="! layout"
  line="  $layout	$description"

  if grep -qFx "$line" "$file"; then
    return
  fi

  add_comment_block "$file"
  awk -v header="$header" -v line="$line" '
    /\/\/ End generated by KLFC/ {
      print header
      print line
      print ""
    }
    { print }
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

copy_file "$xkb_dir_from/symbols/$layout" "$xkb_dir_to/symbols/$layout"
copy_file "$xkb_dir_from/types/$layout" "$xkb_dir_to/types/$layout"
copy_file "$xkb_dir_from/keycodes/$layout" "$xkb_dir_to/keycodes/$layout"

add_type "$xkb_dir_to/rules/base" "$layout"
add_type "$xkb_dir_to/rules/evdev" "$layout"

add_models "$xkb_dir_to/rules/base" "$mods" "$layout"
add_models "$xkb_dir_to/rules/evdev" "$mods" "$layout"

add_description "$xkb_dir_to/rules/base.lst" "$layout" "$description"
add_description "$xkb_dir_to/rules/evdev.lst" "$layout" "$description"

"$xkb_dir_from/scripts/add-layout-to-xml.py" "$xkb_dir_to/rules/base.xml" "$layout" "$description"
"$xkb_dir_from/scripts/add-layout-to-xml.py" "$xkb_dir_to/rules/evdev.xml" "$layout" "$description"

if [ "$(id -u)" -eq 0 ]; then
  if [ "$(cat "$xkb_dir_from/XCompose" | wc -l)" -gt 2 ]; then
    echo "Run install-xcompose.sh as user to install the XCompose file."
    echo "This is needed to make ligatures and custom dead keys work correctly."
  fi
else
  "$xkb_dir_from/install-xcompose.sh" "$layout"
fi
