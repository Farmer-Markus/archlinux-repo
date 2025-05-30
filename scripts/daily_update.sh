#!/bin/bash

TEMP_DIR="/home/markus/Projekte/archlinux-repo/scripts"

# Exit script if error occures
set -e
cd ..

packages=""
packages_need_update=""

get_packages() {
  local package_files=*/*".pkg.tar.zst"
  
  for i in $package_files; do
    local pkg_name=$(tar -xOvf "$i" .PKGINFO 2>/dev/null | grep "^pkgname" | cut -d '=' -f2 | xargs)
    
    if [[ -z "$pkg_name" ]]; then
      continue
    fi
    
    packages="$packages $pkg_name"
  done
}

check_package_updates() {
  for i in $packages; do
    local current_commit=$(curl -s https://api.github.com/repos/Farmer-Markus/$i/commits/main | jq -r '.sha')
    local latest_commit=$(cat "workflow_data/"$i".commit" 2>>/dev/null)
    
    if [ "$current_commit" == "null" ]; then
      continue
    fi
    
    if [ "$current_commit" != "$latest_commit" ]; then
      packages_need_update="$packages_need_update $i"
      update_package $i $current_commit
    fi
  done
}

update_package() {
  local package="neofetch"
  local commit=$2
  
  echo "Updating package: $package"
  if [ -d "$TEMP_DIR/$package" ]; then
      rm -rf "$TEMP_DIR/$package"
  fi
  git clone "https://gitlab.archlinux.org/archlinux/packaging/packages/"$package".git" "$TEMP_DIR/$package"
  
  
  # Source download links überprüfen
  local pkg_var_source=$(awk '/^source=\(/ {in_block=1; print; next} in_block {print; if (/\)/) {in_block=0; exit}}' "$TEMP_DIR/$package/PKGBUILD")
  echo "SOURCE: $pkg_var_source"
  # Mit meinem Link ersetzen
  pkg_var_source=$(echo "$pkg_var_source" | sed -E 's|\S*\'$package'\S*|"git+https://github.com/Farmer-Markus/'$package'"|g')
  # Leerzeichen durch \n ersetzen um sed errors zu vermeiden
  pkg_var_source=$(echo "$pkg_var_source" | sed ':a;N;$!ba;s/\n/\\n/g')
  # "source" variabel zurück in die Datei schreiben
  sed -i "/^source=/,/^)/c\\$pkg_var_source" "$TEMP_DIR/$package/PKGBUILD"
  
  
  # Zeile bekommen um Zeile für b2sums zu wissen
  local pkg_var_source_line=$(echo "$pkg_var_source" | grep -n "Farmer-Markus" | cut -d: -f1)
  # Source b2sums überprüfen
  local pkg_var_b2sums=$(awk '/^b2sums=\(/ {in_block=1; print; next} in_block {print; if (/\)/) {in_block=0; exit}}' "$TEMP_DIR/$package/PKGBUILD")
  # Durch 'SKIP' ersetzen
  pkg_var_b2sums=$(echo "$pkg_var_b2sums" | sed "${pkg_var_source_line}s/'[^']*'/'SKIP'/")
  # Leerzeichen durch \n ersetzen um sed errors zu vermeiden
  pkg_var_b2sums=$(echo "$pkg_var_b2sums" | sed ':a;N;$!ba;s/\n/\\n/g')
  sed -i "/^b2sums=/,/^)/c\\$pkg_var_b2sums" "$TEMP_DIR/$package/PKGBUILD"
  echo "$pkg_var_b2sums"
  
  
  exit
  
  sed -i "s/^b2sums=.*/b2sums=('SKIP'/" "$TEMP_DIR/$package/PKGBUILD"
  
  
  docker pull archlinux:latest
  docker run --rm -v "$TEMP_DIR/$package":/mnt/repo archlinux:latest bash -c "
  pacman -Sy --noconfirm base-devel git sudo
  
  useradd -m builder
  echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
  
  chown -R builder:builder /mnt/repo
  
  su builder -c '
      cd /mnt/repo
      makepkg -s --noconfirm
  '
  "
  
  
  
  
  echo "$commit" > "workflow_data/"$package".commit"
}

get_packages
check_package_updates
echo $packages_need_update

