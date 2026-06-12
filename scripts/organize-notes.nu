#!/usr/bin/env nix-shell
#!nix-shell -i nu -p nushell

let vault_path = ($env.HOME | path join "Documents/Notes")

if not ($vault_path | path exists) {
    print $"📂 Creating Obsidian Vault directory at ($vault_path)..."
    mkdir $vault_path
}

print $"📂 Organizing Vault: ($vault_path)"

# 1. Create PARA Structure
let dirs = ["Inbox", "Areas", "Resources", "Archives", "Attachments"]
for d in $dirs {
    let p = ($vault_path | path join $d)
    if not ($p | path exists) {
        mkdir $p
    }
}

# 2. Move root files to appropriate folders
def move_if_exists [src: string, target: string] {
    if $src == $target {
        return
    }
    let vault = ($env.HOME | path join "Documents/Notes")
    let source = ($vault | path join $src)
    let dest = ($vault | path join $target)
    if ($source | path exists) {
        print $"   Moving ($src) -> ($target)/"
        mv $source $dest
    }
}

# --- Move Directories ---
move_if_exists "Finance" "Areas"
move_if_exists "Taekwondo" "Areas"
move_if_exists "Learning" "Resources"
move_if_exists "Chrome Os Flex" "Resources"
move_if_exists "Projects" "Projects"

# --- Move Files ---
move_if_exists "temp.md" "Inbox"
move_if_exists "Eltern Sport.md" "Areas"

# --- Move Attachments (Images) ---
try {
    ls ($vault_path | path join "*.png") | each { |it| mv $it.name ($vault_path | path join "Attachments") }
}
try {
    ls ($vault_path | path join "*.jpg") | each { |it| mv $it.name ($vault_path | path join "Attachments") }
}

print "✅ Organization complete!"
