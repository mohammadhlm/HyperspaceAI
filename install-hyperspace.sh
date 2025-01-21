#!/bin/bash

# Function to display the header
show_header() {
    clear
    echo "==============================================="
    echo "    Installation and Configuration of Hyperspace Node"
    echo "==============================================="
    echo "Subscribe to our Telegram channel @nodetrip"
    echo "for the latest updates and support"
    echo "==============================================="
    echo
}

# Function to display instructions
show_instructions() {
    show_header
    echo "Simple Installation of Hyperspace Node:"
    echo "1. Install the node"
    echo "2. Insert your private key"
    echo "3. Select tier based on RAM"
    echo "   (tier 3 for RAM > 8GB, tier 5 for RAM < 8GB)"
    echo "4. Wait for the first points to be credited (~30-60 minutes)"
    echo
    echo "Press Enter to continue..."
    read
}

# Main menu
show_menu() {
    show_header
    echo "Select an action:"
    echo "1. Install Hyperspace Node"
    echo "2. Node Management"
    echo "3. Status Check"
    echo "4. Delete Node"
    echo "5. Show Instructions"
    echo "6. Exit"
    echo
    echo -n "Your choice (1-6): "
}

# Node management menu
node_menu() {
    show_header
    if ! check_installation; then
        echo "Error: aios-cli not installed. Please install first (option 1)"
        echo "Press Enter to continue..."
        read
        return
    fi
    echo "Node Management:"
    echo "1. Start Node"
    echo "2. Select Tier"
    echo "3. Add Default Model"
    echo "4. Connect to Hive"
    echo "5. Check Earned Points"
    echo "6. Model Management"
    echo "7. Check Connection Status"
    echo "8. Stop Node"
    echo "9. Restart with Cleanup"
    echo "10. Return to Main Menu"
    echo
    echo -n "Your choice (1-10): "
}

# Function to set up and configure keys
setup_keys() {
    # Check for existing keys
    if [ -f my.pem ]; then
        echo "Existing key file found."
        echo -n "Do you want to use a new key? (y/N): "
        read replace_key
        if [[ $replace_key != "y" && $replace_key != "Y" ]]; then
            echo "Continue using the existing key."
            return
        fi
    fi

    echo "Enter your private key:"
    read private_key
    
    # Clean up the key from unnecessary characters
    private_key=$(echo "$private_key" | tr -d '[:space:]')
    
    # Save the key
    echo "$private_key" > my.pem
    chmod 600 my.pem
    
    # Check the contents of the file
    echo "Checking the saved key:"
    hexdump -C my.pem
    
    if command -v aios-cli &> /dev/null; then
        # Stop all processes
        echo "Stopping old processes..."
        aios-cli kill
        pkill -f "aios"
        
        # Close all screen sessions
        echo "Closing screen sessions..."
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        # Save the binary file
        if [ -f ~/.aios/aios-cli ]; then
            mv ~/.aios/aios-cli /tmp/
        fi
        rm -rf ~/.aios/*
        mkdir -p ~/.aios
        if [ -f /tmp/aios-cli ]; then
            mv /tmp/aios-cli ~/.aios/
        fi
        
        # Reinstall
        echo "Reinstalling aios-cli..."
        curl https://download.hyper.space/api/install | bash
        source /root/.bashrc
        sleep 5
        
        # Close all screen sessions
        echo "Closing screen sessions..."
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        # Start the daemon in screen with logging
        echo "Starting aios-cli..."
        screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
        sleep 10
        
        # Check if the process is running
        if ! ps aux | grep -q "[_]aios-kernel"; then
            echo "Error: process not running"
            echo "Checking the daemon logs..."
            tail -n 50 ~/.aios/screen.log
            return 1
        fi
        
        # First, import the key
        echo "Importing the key..."
        aios-cli hive import-keys ./my.pem
        sleep 5
        
        # Log in
        echo "Logging in..."
        aios-cli hive login
        sleep 5
        
        # Check if the key is imported
        if ! aios-cli hive whoami | grep -q "Public:"; then
            echo "Error: key not imported"
            return 1
        fi
        
        # Connect to Hive
        echo "Connecting to Hive..."
        aios-cli hive connect
        sleep 10
        
        # Set the tier
        echo "Setting the tier..."
        aios-cli hive select-tier 5
        sleep 10
        
        # Check the tier
        if ! aios-cli hive points | grep -q "Tier: 5"; then
            echo "Error: unable to set the tier"
            return 1
        fi
        
        # Add the model
        echo "Adding the model..."
        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
        sleep 10
        
        # Check if the model is downloaded
        echo "Checking the model status..."
        if ! aios-cli models list | grep -q "phi-2"; then
            echo "Waiting for the model to download..."
            for i in {1..12}; do  # Wait for a maximum of 2 minutes
                if aios-cli models list | grep -q "phi-2"; then
                    break
                fi
                echo -n "."
                sleep 10
            done
        fi
        
        # Check if the model is initialized
        echo "Checking the model initialization..."
        if ! grep -q "llm_load_print_meta: model size" ~/.aios/screen.log; then
            echo "Waiting for the model initialization..."
            for i in {1..6}; do  # Wait for a maximum of 1 minute
                if grep -q "llm_load_print_meta: model size" ~/.aios/screen.log; then
                    break
                fi
                echo -n "."
                sleep 10
            done
        fi
        
        # If the model is not registered, restart
        if aios-cli hive whoami | grep -q "Failed to register models"; then
            echo "Restarting the daemon to register the model..."
            aios-cli kill
            pkill -f "aios"
            sleep 3
            
            screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
            sleep 10
            
            # Check if the screen session is created
            if ! screen -ls | grep -q "Hypernodes"; then
                echo "Error: screen session not created"
                return 1
            fi
            
            aios-cli hive connect
            sleep 5
            
            # Check the status
            echo "Checking the status..."
            aios-cli hive whoami
            aios-cli models list
            
            # Final check
            if ! aios-cli hive whoami | grep -q "Successfully connected"; then
                echo "Error: unable to connect to Hive"
                return 1
            fi
            
            echo " Node successfully configured and ready to work!"
        fi
    else
        echo "Error: aios-cli not found"
    fi
}

# Function to check the installation
check_installation() {
    if ! command -v aios-cli &> /dev/null; then
        echo "aios-cli not found. Restarting the environment..."
        export PATH="$PATH:/root/.aios"
        source /root/.bashrc
        
        if ! command -v aios-cli &> /dev/null; then
            return 1
        fi
    fi
    return 0
}

# Function to check the node status
check_node_status() {
    echo "Checking the node status..."
    
    # Check if the node is running
    if ! ps aux | grep -q "[_]aios-kernel"; then
        echo " Node not running"
        echo "Starting the node..."
        
        # Stop all processes
        aios-cli kill
        pkill -f "aios"
        sleep 3
        
        # Close all screen sessions
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        # Start the daemon
        screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
        sleep 10
        
        # Check if the process is running
        if ! ps aux | grep -q "[_]aios-kernel"; then
            echo "Error: unable to start the node"
            return 1
        fi
        
        # Log in
        echo "Logging in..."
        aios-cli hive login
        sleep 5
    fi
    
    # Check and restore the connection to Hive
    echo "Checking the connection to Hive..."
    max_attempts=3
    attempt=1
    connected=false
    
    while [ $attempt -le $max_attempts ]; do
        if aios-cli hive whoami 2>&1 | grep -q "Public:"; then
            connected=true
            echo " Successfully connected to Hive"
            break
        fi
        echo "Attempt $attempt out of $max_attempts to connect to Hive..."
        aios-cli hive connect
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ "$connected" = false ]; then
        echo " Unable to connect to Hive after $max_attempts attempts"
        echo "Trying to restart the node..."
        aios-cli kill
        sleep 5
        screen -dmS Hypernodes aios-cli start
        sleep 10
        aios-cli hive login
        sleep 5
        aios-cli hive connect
    fi
    
    # Check the status
    echo "1. Checking the keys:"
    aios-cli hive whoami
    
    echo "2. Checking the points:"
    if ! aios-cli hive points; then
        echo "Error getting points, checking the connection to Hive"
        echo "Trying to restore the connection..."
        aios-cli hive login
        sleep 5
        aios-cli hive connect
        sleep 5
        echo "Rechecking the points..."
        aios-cli hive points
    fi
    
    echo "3. Checking the models:"
    echo "Active models:"
    aios-cli models list
    echo
    echo "Available models:"
    aios-cli models available
    
    return 0
}

# Function to diagnose the installation
diagnose_installation() {
    echo "=== Installation Diagnostics ==="
    echo "1. Checking the paths:"
    echo "PATH=$PATH"
    echo
    echo "2. Checking the binary file:"
    ls -l /root/.aios/aios-cli
    echo
    echo "3. Checking the version:"
    /root/.aios/aios-cli hive version
    echo
    echo "4. Checking the configuration:"
    ls -la ~/.aios/
    echo
    echo "5. Checking the network connection:"
    curl -Is https://download.hyper.space | head -1
    echo
    echo "6. Checking the service status:"
    ps aux | grep aios-cli
    echo
    echo "7. Checking the logs:"
    tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Logs not found"
    echo
    echo "=== End of Diagnostics ==="
}

# Function to check if the node is running
check_node_running() {
    if pgrep -f "__aios-kernel" >/dev/null || pgrep -f "aios-cli start" >/dev/null; then
        echo "Node already running"
        ps aux | grep -E "aios-cli|__aios-kernel" | grep -v grep
        return 0
    fi
    return 1
}

# Function to check and restore the connection
check_connection() {
    echo "Checking the connection to Hive..."
    if ! aios-cli hive whoami | grep -q "Public:"; then
        echo " Lost connection to Hive"
        echo "Trying to restore..."
        
        # Stop processes
        aios-cli kill
        pkill -f "aios"
        sleep 3
        
        # Restart the daemon
        screen -dmS Hypernodes aios-cli start
        sleep 10
        
        # Reconnect
        aios-cli hive login
        sleep 5
        aios-cli hive connect
        sleep 5
        
        if aios-cli hive whoami | grep -q "Public:"; then
            echo " Connection restored"
            return 0
        else
            echo " Unable to restore the connection"
            return 1
        fi
    else
        echo " Connection active"
        return 0
    fi
}

# Main logic
while true; do
    show_menu
    read choice
    case $choice in
        1)
            show_header
            echo "Installing Hyperspace Node..."
            curl https://download.hyper.space/api/install | bash
            
            # Restart the environment
            # Check if the path is already added
            if ! echo $PATH | grep -q "/root/.aios"; then
                export PATH="$PATH:/root/.aios"
            fi
            source /root/.bashrc
            
            # Automatic key setup after installation
            echo "Waiting 5 seconds for the system to initialize..."
            sleep 5
            
            if ! command -v aios-cli &> /dev/null; then
                echo "Error: aios-cli not installed correctly."
                echo "Try running the following commands manually:"
                echo "1. source /root/.bashrc"
                echo "2. aios-cli hive import-keys ./my.pem"
                echo "Press Enter to continue..."
                read
                continue
            fi
            
            setup_keys
            
            echo "Installation complete. Press Enter to continue..."
            read
            ;;
        2)
            while true; do
                node_menu
                read node_choice
                case $node_choice in
                    1)
                        echo "Clearing old sessions..."
                        if check_node_running; then
                            echo "Node already running. Do you want to restart? (y/N): "
                            read restart
                            if [[ $restart != "y" && $restart != "Y" ]]; then
                                echo "Canceling the start"
                                return
                            fi
                        fi
                        # First, stop the existing processes
                        echo "Stopping existing processes..."
                        pkill -f "__aios-kernel" || true
                        pkill -f "aios-cli start" || true
                        sleep 2
                        
                        # Find and close all Hypernodes sessions
                        screen -ls | grep Hypernodes | cut -d. -f1 | while read pid; do
                            echo "Closing session with PID: $pid"
                            kill $pid 2>/dev/null || true
                        done
                        sleep 2
                        
                        # Fix the PATH
                        export PATH="/root/.aios:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                        
                        echo "Starting the node..."
                        echo "Starting in screen..."
                        screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                        echo "Waiting for the node to start..."
                        start_time=$(date +%s)
                        timeout=300  # 5-minute timeout
                        
                        while true; do
                            current_time=$(date +%s)
                            elapsed=$((current_time - start_time))
                            
                            # Check the processes
                            if ps aux | grep -q "[_]aios-kernel"; then
                                if aios-cli hive whoami | grep -q "Public"; then
                                    echo " Node successfully started and connected"
                                    break
                                fi
                            fi
                            
                            # Check the timeout
                            if [ $elapsed -gt $timeout ]; then
                                echo " Timeout exceeded"
                                echo "Restarting the node..."
                                pkill -9 -f "aios"
                                sleep 2
                                screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                                sleep 5
                                break
                            fi
                            
                            echo -n "."
                            sleep 5
                        done
                        
                        # Check if the node started
                        if screen -ls | grep -q "Hypernodes"; then
                            echo "Node successfully started"
                            # Check the process
                            ps aux | grep "[a]ios-cli"
                            echo "Checking the startup log..."
                            screen -r Hypernodes -X hardcopy .screen.log
                            echo "Last logs:"
                            tail -n 5 .screen.log
                        else
                            echo "Error: Node not started"
                            echo "Checking the environment:"
                            echo "PATH=$PATH"
                            echo "Checking the processes:"
                            ps aux | grep "[a]ios"
                            echo "Trying an alternative way to start..."
                            screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                            sleep 5
                            if screen -ls | grep -q "Hypernodes"; then
                                echo "Node started in an alternative way"
                                ps aux | grep "[a]ios-cli"
                            else
                                echo "Error: Unable to start the node"
                                echo "Last errors:"
                                tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Logs not found"
                            fi
                        fi
                        echo "Node started in screen session 'Hypernodes'"
                        echo "To view the logs, use the command: screen -r Hypernodes"
                        echo "To exit the logs, press Ctrl+A, then D"
                        echo "Press Enter to continue..."
                        read
                        ;;
                    2)
                        # First, check the node status and connection
                        echo "Checking the status before setting the tier..."
                        echo "1. Checking the processes:"
                        ps aux | grep "[a]ios"
                        echo
                        echo "2. Checking the connection:"
                        if ! aios-cli hive whoami | grep -q "Public:"; then
                            echo " Node not connected to Hive"
                            echo "First, log in:"
                            aios-cli hive login
                            sleep 2
                        fi
                        
                        echo "Select the tier (3 for RAM > 8GB, 5 for RAM < 8GB):"
                        echo "Tier recommendations:"
                        echo "- Tier 5: for light models (phi-2 ~1.67GB)"
                        echo "- Tier 3: for heavy models (>8GB RAM)"
                        read tier
                        echo "Setting tier $tier..."
                        # Try several times
                        max_attempts=3
                        attempt=1
                        success=false
                        while [ $attempt -le $max_attempts ]; do
                            echo "Attempt $attempt out of $max_attempts to set the tier..."
                            if aios-cli hive select-tier $tier 2>&1 | grep -q "Failed"; then
                                echo " Attempt $attempt failed"
                                sleep 5
                            else
                                success=true
                                break
                            fi
                            attempt=$((attempt + 1))
                        done
                        
                        if [ "$success" = true ]; then
                            echo " Tier $tier successfully set"
                            echo "Checking the connection:"
                            aios-cli hive whoami
                        else
                            echo " Error setting the tier"
                            echo "Trying an alternative way..."
                            echo "1. Restart the environment"
                            source /root/.bashrc
                            sleep 2
                            echo "2. Check the login"
                            aios-cli hive login
                            sleep 2
                            echo "3. Try to set the tier again"
                            aios-cli hive select-tier $tier
                            echo "Checking the node status:"
                            ps aux | grep "[a]ios"
                            echo
                            echo "Checking the logs:"
                            tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Logs not found"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    3)
                        echo "Adding the default model..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        echo
                        echo "Checking the active models:"
                        aios-cli models list
                        echo
                        if aios-cli models list | grep -q "phi-2"; then
                            echo " Model phi-2 successfully added"
                        else
                            echo " Error: Model not found in the active list"
                            echo "Try adding the model again"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    4)
                        echo "Connecting to Hive..."
                        echo "1. Stopping the current processes..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        
                        echo "2. Starting the node again..."
                        echo "Checking the keys..."
                        
                        echo "Enter your private key:"
                        read private_key
                        echo "$private_key" > my.pem
                        chmod 600 my.pem
                        
                        echo "Importing the keys..."
                        aios-cli hive import-keys ./my.pem
                        sleep 2
                        
                        echo "Logging in..."
                        aios-cli hive login
                        sleep 2
                        
                        echo "Setting tier 5..."
                        aios-cli hive select-tier 5
                        sleep 2
                        
                        echo "Starting in screen..."
                        screen -dmS Hypernodes aios-cli start
                        sleep 2
                        
                        echo "Adding the phi-2 model..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        sleep 2
                        
                        echo "Connecting to Hive..."
                        aios-cli hive connect
                        sleep 5
                        
                        echo "Checking the node status..."
                        if aios-cli hive whoami | grep -q "Public:"; then
                            echo " Node ready to work"
                        else
                            echo " Error connecting"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    5)
                        echo "Checking the earned points..."
                        aios-cli hive points
                        echo "Press Enter to continue..."
                        read
                        ;;
                    6)
                        echo "Model Management:"
                        echo "1. Active models:"
                        aios-cli models list
                        echo
                        echo "2. Available models:"
                        aios-cli models available
                        echo "Press Enter to continue..."
                        read
                        ;;
                    7)
                        echo "Checking the connection status..."
                        echo "1. Connection status:"
                        aios-cli hive whoami
                        echo
                        echo "2. Checking the points:"
                        aios-cli hive points
                        echo
                        echo "3. Checking the models:"
                        aios-cli models available
                        echo "Press Enter to continue..."
                        read
                        ;;
                    8)
                        echo "Stopping the node..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        
                        # Check if the processes stopped
                        if pgrep -f "aios" > /dev/null; then
                            echo " Unable to stop all processes"
                            echo "Active processes:"
                            ps aux | grep "[a]ios"
                        else
                            echo " Node successfully stopped"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    9)
                        echo "Performing a full restart with cleanup..."
                        echo "1. Stopping all processes..."
                        aios-cli kill
                        pkill -f "aios"
                        sleep 2
                        
                        echo "2. Restarting the environment..."
                        source /root/.bashrc
                        sleep 2
                        
                        echo "3. Starting the node..."
                        aios-cli start
                        sleep 5
                        
                        echo "4. Logging in..."
                        aios-cli hive login
                        sleep 2
                        
                        echo "5. Setting tier 3..."
                        aios-cli hive select-tier 3
                        sleep 2
                        
                        echo "6. Adding the phi-2 model..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        sleep 2
                        
                        echo "7. Connecting to Hive..."
                        aios-cli hive connect
                        
                        echo "8. Checking the status..."
                        echo "Connection status:"
                        aios-cli hive whoami
                        echo
                        echo "Active models:"
                        aios-cli models list
                        
                        echo "Press Enter to continue..."
                        read
                        ;;
                    10)
                        break
                        ;;
                esac
            done
            ;;
        3)
            show_header
            check_node_status
            echo "Press Enter to continue..."
            read
            ;;
        4)
            show_header
            echo "Attention! You are going to delete the Hyperspace node."
            echo "This action will delete only the files and settings of the Hyperspace Node."
            echo "Other installed nodes will not be affected."
            echo
            echo -n "Are you sure? (y/N): "
            read confirm
            if [[ $confirm == "y" || $confirm == "Y" ]]; then
                echo "Stopping the Hyperspace node..."
                aios-cli kill
                echo "Deleting the Hyperspace node files..."
                if [ -d ~/.aios ]; then
                    echo "Found the ~/.aios directory"
                    echo -n "Delete ~/.aios? (y/N): "
                    read confirm_aios
                    if [[ $confirm_aios == "y" || $confirm_aios == "Y" ]]; then
                        rm -rf ~/.aios
                        echo "Directory ~/.aios deleted"
                    fi
                fi
                
                if [ -f my.pem ]; then
                    echo -n "Delete the file my.pem? (y/N): "
                    read confirm_pem
                    if [[ $confirm_pem == "y" || $confirm_pem == "Y" ]]; then
                        rm -f my.pem
                        echo "File my.pem deleted"
                    fi
                fi
                
                echo "Deleting the installed packages..."
                echo "To completely delete the packages, run the command:"
                echo "apt remove aios-cli (if installed via apt)"
                echo "Node successfully deleted."
                echo "Press Enter to continue..."
                read
            else
                echo "Deletion canceled."
                echo "Press Enter to continue..."
                read
            fi
            ;;
        5)
            show_instructions
            ;;
        6)
            echo "Thank you for using the installer!"
            echo "Don't forget to subscribe to @nodetrip on Telegram"
            exit 0
            ;;
    esac
done

# Add a check to the main loop
while true; do
    check_connection
    sleep 300 # Check every 5 minutes
done &
