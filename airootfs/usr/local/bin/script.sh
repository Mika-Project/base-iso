#!/bin/bash

output_file=$(mktemp)

run_command() {
    command="$1"
    eval "$command" 2>&1 | tee "$output_file"
    return ${PIPESTATUS[0]}
}

# zenity --info --title="Mika System Updater" --text="Welcome to the Mika System updater, to update your system please select the 'Update System' option and click on 'OK' to confirm."
choice=$(zenity --list --title="Mika System Updater" --text="Welcome to the Mika System updater, to update your system please select the 'Update System' option and click on 'OK' to confirm. Please choose an action:" --column="Options" "Update System" "Update Databases" "Exit")

case "$choice" in
    "Update System")
        if yay -V >/dev/null 2>&1; then
            run_command "yay -Syyu"
        else
            run_command "sudo pacman -Syyu"
        fi
        exit_status=$?

        if [ $exit_status -eq 0 ]; then
            zenity --info --text="System update succeeded. You can now close the terminal window."
        else
            zenity --error --text="System update failed. Check the command output for details. You can now close the terminal window."
        fi
        ;;
    "Update Databases")
        if yay -V >/dev/null 2>&1; then
            run_command "yay -Syy"
        else
            run_command "sudo pacman -Syy"
        fi
        exit_status=$?

        if [ $exit_status -eq 0 ]; then
            zenity --info --text="Database update succeeded. You can now close the terminal window."
        else
            zenity --error --text="Database update failed. Check the command output for details. You can now close the terminal window."
        fi
        ;;
    "Exit")
        zenity --info --text="Exiting Mika System Updater."
        exit
        ;;
    *)
        zenity --error --text="Invalid choice."
        exit
        ;;
esac

rm "$output_file"
