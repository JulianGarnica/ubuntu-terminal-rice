#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.RiceBackup/ubuntu-terminal-$(date +%Y%m%d-%H%M%S)"

info() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m!!\033[0m %s\n' "$1"
}

die() {
  printf '\033[1;31mError:\033[0m %s\n' "$1" >&2
  exit 1
}

backup_path() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$path" "$BACKUP_DIR/"
    info "Backup: $path -> $BACKUP_DIR/"
  fi
}

require_file() {
  [ -e "$DOTFILES_DIR/$1" ] || die "No encontré $DOTFILES_DIR/$1"
}

install_packages() {
  info "Instalando paquetes base con apt"
  sudo apt update
  sudo apt install -y \
    alacritty \
    kitty \
    zsh \
    git \
    curl \
    unzip \
    fzf \
    bat \
    fonts-jetbrains-mono \
    zsh-autosuggestions \
    zsh-syntax-highlighting

  sudo apt install -y eza || warn "No pude instalar eza desde apt; usaré ls como fallback."
}

install_nerd_font() {
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerd"

  info "Instalando JetBrainsMono Nerd Font"
  mkdir -p "$font_dir"

  local tmp_zip
  tmp_zip="$(mktemp /tmp/JetBrainsMonoNerd.XXXXXX.zip)"

  curl -fL \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" \
    -o "$tmp_zip"

  unzip -o "$tmp_zip" -d "$font_dir" >/dev/null
  rm -f "$tmp_zip"
  fc-cache -fv >/dev/null
}

copy_dotfiles() {
  info "Copiando configs de Alacritty, Kitty, Zsh y scripts locales"

  require_file "config/alacritty"
  require_file "config/kitty"
  require_file "config/zsh"
  require_file "home/.zshrc"
  require_file "misc/asciiart"
  require_file "misc/bin"
  require_file "misc/fonts"

  mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share"

  backup_path "$HOME/.config/alacritty"
  backup_path "$HOME/.config/kitty"
  backup_path "$HOME/.config/zsh"
  backup_path "$HOME/.zshrc"
  backup_path "$HOME/.local/share/asciiart"
  backup_path "$HOME/.local/bin/colorscript"
  backup_path "$HOME/.local/bin/sysfetch"
  backup_path "$HOME/.local/share/fonts/dotfiles-terminal"

  cp -R "$DOTFILES_DIR/config/alacritty" "$HOME/.config/"
  cp -R "$DOTFILES_DIR/config/kitty" "$HOME/.config/"
  cp -R "$DOTFILES_DIR/config/zsh" "$HOME/.config/"
  cp -R "$DOTFILES_DIR/misc/asciiart" "$HOME/.local/share/"
  cp -R "$DOTFILES_DIR/misc/fonts" "$HOME/.local/share/fonts/dotfiles-terminal"
  cp "$DOTFILES_DIR/misc/bin/colorscript" "$HOME/.local/bin/colorscript"
  cp "$DOTFILES_DIR/misc/bin/sysfetch" "$HOME/.local/bin/sysfetch"
  cp "$DOTFILES_DIR/home/.zshrc" "$HOME/.zshrc"
  chmod +x "$HOME/.local/bin/colorscript"
  chmod +x "$HOME/.local/bin/sysfetch"
  fc-cache -fv >/dev/null
}

patch_ubuntu_paths() {
  info "Adaptando .zshrc para Ubuntu"

  mkdir -p "$HOME/.local/bin"

  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
  fi

  sudo mkdir -p \
    /usr/share/zsh/plugins/zsh-autosuggestions \
    /usr/share/zsh/plugins/zsh-syntax-highlighting \
    /usr/share/zsh/plugins/zsh-history-substring-search

  if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    sudo ln -sf /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
      /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
  fi

  if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    sudo ln -sf /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
      /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  fi

  if [ -f /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
    sudo ln -sf /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh \
      /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
  fi

  if [ ! -f /usr/share/zsh/plugins/fzf-tab-git/fzf-tab.zsh ]; then
    sudo git clone --depth=1 https://github.com/Aloxaf/fzf-tab \
      /usr/share/zsh/plugins/fzf-tab-git
  fi

  if [ ! -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
    sudo git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search \
      /usr/share/zsh/plugins/zsh-history-substring-search
  fi

  # Icono de Ubuntu en el prompt, en lugar del icono de Arch del dotfile original.
  sed -i 's/%B%F{blue}%f%b/%B%F{blue}%f%b/' "$HOME/.zshrc"

  # Evita aliases de Arch en Ubuntu.
  sed -i \
    -e 's/^alias mirrors=/# alias mirrors=/' \
    -e 's/^alias update=/# alias update=/' \
    -e 's/^alias grub-update=/# alias grub-update=/' \
    "$HOME/.zshrc"

  if ! command -v eza >/dev/null 2>&1; then
    sed -i \
      -e "s/^alias ls=.*/alias ls='ls -a --color=auto'/" \
      -e "s/^alias ll=.*/alias ll='ls -la --color=auto'/" \
      "$HOME/.zshrc"
  fi
}

change_shell() {
  local zsh_path
  zsh_path="$(command -v zsh)"

  if [ "${SHELL:-}" != "$zsh_path" ]; then
    info "Cambiando shell por defecto a zsh"
    chsh -s "$zsh_path"
  else
    info "zsh ya es tu shell por defecto"
  fi
}

main() {
  [ -d "$DOTFILES_DIR/config" ] || die "Ejecuta este script desde el repo de dotfiles."

  install_packages
  install_nerd_font
  copy_dotfiles
  patch_ubuntu_paths
  change_shell

  info "Listo. Cierra sesión y vuelve a entrar; luego abre Alacritty o Kitty."
  info "Backups, si hubo, quedaron en: $BACKUP_DIR"
}

main "$@"
