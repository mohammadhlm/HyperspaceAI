#!/bin/bash

# Function to set up the model at the very beginning
setup_model() {
    echo -n "Enter the model to use (e.g., hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf): "
    read MODEL
    export MODEL
}

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
    echo "3. By default, Tier 3 will be selected and installed"
    echo "4. The installation process will also display resource usage"
    echo "   (CPU and Memory) of the related processes."
    echo
    echo "Press Enter to continue..."
    read
}

# Function to show resource consumption for aios-cli and aios-kernel processes
show_resource_usage() {
    echo "-----------------------------------------------"
    echo "Resource usage for 'aios-cli' processes:"
    ps -C aios-cli -o pid,%cpu,%mem,cmd
    echo "-----------------------------------------------"
    echo "Resource usage for 'aios-kernel' processes:"
    ps -C aios-kernel -o pid,%cpu,%mem,cmd
    echo "-----------------------------------------------"
    echo "Press Enter to return to the main menu..."
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
    echo "6. Check Resource Consumption"
    echo "7. Exit"
    echo
    echo -n "Your choice (1-7): "
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
    echo "3. Add Model"
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

# Function to set up and configure keys, now using default Tier 3
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
    
    # Clean up key of unnecessary spaces and newlines
    private_key=$(echo "$private_key" | tr -d '[:space:]')
    echo "$private_key" > my.pem
    chmod 600 my.pem
    
    echo "Checking the saved key:"
    hexdump -C my.pem
    
    if command -v aios-cli &> /dev/null; then
        echo "Stopping old processes..."
        aios-cli kill
        pkill -f "aios"
        
        echo "Closing screen sessions..."
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        if [ -f ~/.aios/aios-cli ]; then
            mv ~/.aios/aios-cli /tmp/
        fi
        rm -rf ~/.aios/*
        mkdir -p ~/.aios
        if [ -f /tmp/aios-cli ]; then
            mv /tmp/aios-cli ~/.aios/
        fi
        
        echo "Reinstalling aios-cli..."
        curl https://download.hyper.space/api/install | bash
        source /root/.bashrc
        sleep 5
        
        echo "Closing screen sessions..."
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        echo "Starting aios-cli..."
        screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
        sleep 10
        
        if ! ps aux | grep -q "[_]aios-kernel"; then
            echo "Error: process not running"
            tail -n 50 ~/.aios/screen.log
            return 1
        fi
        
        echo "Importing the key..."
        aios-cli hive import-keys ./my.pem
        sleep 5
        
        echo "Logging in..."
        aios-cli hive login
        sleep 5
        
        if ! aios-cli hive whoami | grep -q "Public:"; then
            echo "Error: key not imported"
            return 1
        fi
        
        echo "Connecting to Hive..."
        aios-cli hive connect
        sleep 10
        
        # Default Tier set to 3
        echo "Setting the tier to 3 (default)..."
        aios-cli hive select-tier 3
        sleep 10
        
        if ! aios-cli hive points | grep -q "Tier: 3"; then
            echo "Error: unable to set tier 3"
            return 1
        fi
        
        echo "Adding the model ${MODEL}..."
        aios-cli models add "$MODEL"
        sleep 10
        
        echo "Checking the model status..."
        model_short=$(echo $MODEL | cut -d: -f2)
        if ! aios-cli models list | grep -q "${model_short}"; then
            echo "Waiting for the model to download..."
            for i in {1..12}; do
                if aios-cli models list | grep -q "${model_short}"; then
                    break
                fi
                echo -n "."
                sleep 10
            done
        fi
        
        echo "Checking the model initialization..."
        if ! grep -q "llm_load_print_meta: model size" ~/.aios/screen.log; then
            echo "Waiting for model initialization..."
            for i in {1..6}; do
                if grep -q "llm_load_print_meta: model size" ~/.aios/screen.log; then
                    break
                fi
                echo -n "."
                sleep 10
            done
        fi
        
        if aios-cli hive whoami | grep -q "Failed to register models"; then
            echo "Restarting daemon to register the model..."
            aios-cli kill
            pkill -f "aios"
            sleep 3
            
            screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
            sleep 10
            
            if ! screen -ls | grep -q "Hypernodes"; then
                echo "Error: screen session not created"
                return 1
            fi
            
            aios-cli hive connect
            sleep 5
            
            echo "Checking the status..."
            aios-cli hive whoami
            aios-cli models list
            
            if ! aios-cli hive whoami | grep -q "Successfully connected"; then
                echo "Error: unable to connect to Hive"
                return 1
            fi
            
            echo "Node successfully configured and ready to work!"
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
    if ! ps aux | grep -q "[_]aios-kernel"; then
        echo "Node not running"
        echo "Starting the node..."
        aios-cli kill
        pkill -f "aios"
        sleep 3
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
        sleep 10
        if ! ps aux | grep -q "[_]aios-kernel"; then
            echo "Error: unable to start the node"
            return 1
        fi
        echo "Logging in..."
        aios-cli hive login
        sleep 5
    fi
    
    echo "Checking the connection to Hive..."
    max_attempts=3
    attempt=1
    connected=false
    
    while [ $attempt -le $max_attempts ]; do
        if aios-cli hive whoami 2>&1 | grep -q "Public:"; then
            connected=true
            echo "Successfully connected to Hive"
            break
        fi
        echo "Attempt $attempt out of $max_attempts to connect to Hive..."
        aios-cli hive connect
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ "$connected" = false ]; then
        echo "Unable to connect to Hive after $max_attempts attempts"
        echo "Trying to restart the node..."
        aios-cli kill
        sleep 5
        screen -dmS Hypernodes aios-cli start
        sleep 10
        aios-cli hive login
        sleep 5
        aios-cli hive connect
    fi
    
    echo "1. Checking the keys:"
    aios-cli hive whoami
    
    echo "2. Checking the points:"
    if ! aios-cli hive points; then
        echo "Error getting points, restoring connection..."
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
        echo "Lost connection to Hive. Restoring..."
        aios-cli kill
        pkill -f "aios"
        sleep 3
        screen -dmS Hypernodes aios-cli start
        sleep 10
        aios-cli hive login
        sleep 5
        aios-cli hive connect
        sleep 5
        if aios-cli hive whoami | grep -q "Public:"; then
            echo "Connection restored"
            return 0
        else
            echo "Unable to restore the connection"
            return 1
        fi
    else
        echo "Connection active"
        return 0
    fi
}

# At the very beginning, ask for the model input
setup_model

# Main logic
while true; do
    show_menu
    read choice
    case $choice in
        1)
            show_header
            echo "Installing Hyperspace Node..."
            curl https://download.hyper.space/api/install | bash
            if ! echo $PATH | grep -q "/root/.aios"; then
                export PATH="$PATH:/root/.aios"
            fi
            source /root/.bashrc
            echo "Waiting 5 seconds for the system to initialize..."
            sleep 5
            if ! command -v aios-cli &> /dev/null; then
                echo "Error: aios-cli not installed correctly."
                echo "Try running:"
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
                                break
                            fi
                        fi
                        echo "Stopping existing processes..."
                        pkill -f "__aios-kernel" || true
                        pkill -f "aios-cli start" || true
                        sleep 2
                        screen -ls | grep Hypernodes | cut -d. -f1 | while read pid; do
                            echo "Closing session with PID: $pid"
                            kill $pid 2>/dev/null || true
                        done
                        sleep 2
                        export PATH="/root/.aios:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                        echo "Starting the node..."
                        screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                        echo "Waiting for the node to start..."
                        start_time=$(date +%s)
                        timeout=300
                        while true; do
                            current_time=$(date +%s)
                            elapsed=$((current_time - start_time))
                            if ps aux | grep -q "[_]aios-kernel"; then
                                if aios-cli hive whoami | grep -q "Public"; then
                                    echo "Node successfully started and connected"
                                    break
                                fi
                            fi
                            if [ $elapsed -gt $timeout ]; then
                                echo "Timeout exceeded. Restarting the node..."
                                pkill -9 -f "aios"
                                sleep 2
                                screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                                sleep 5
                                break
                            fi
                            echo -n "."
                            sleep 5
                        done
                        if screen -ls | grep -q "Hypernodes"; then
                            echo "Node successfully started"
                            ps aux | grep "[a]ios-cli"
                            echo "Checking the startup log..."
                            screen -r Hypernodes -X hardcopy .screen.log
                            echo "Last logs:"
                            tail -n 5 .screen.log
                        else
                            echo "Error: Node not started"
                            echo "Checking the environment:"
                            echo "PATH=$PATH"
                            ps aux | grep "[a]ios"
                            echo "Trying an alternative start method..."
                            screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                            sleep 5
                            if screen -ls | grep -q "Hypernodes"; then
                                echo "Node started alternatively"
                                ps aux | grep "[a]ios-cli"
                            else
                                echo "Error: Unable to start the node"
                                tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Logs not found"
                            fi
                        fi
                        echo "Node started in screen session 'Hypernodes'"
                        echo "To view logs, use: screen -r Hypernodes"
                        echo "Press Enter to continue..."
                        read
                        ;;
                    2)
                        echo "Checking status before setting tier..."
                        echo "1. Processes:"
                        ps aux | grep "[a]ios"
                        echo
                        echo "2. Connection:"
                        if ! aios-cli hive whoami | grep -q "Public:"; then
                            echo "Node not connected to Hive. Logging in..."
                            aios-cli hive login
                            sleep 2
                        fi
                        echo "Select the tier (default is 3; enter 3 or 5):"
                        read tier
                        if [ -z "$tier" ]; then
                            tier=3
                        fi
                        echo "Setting tier $tier..."
                        max_attempts=3
                        attempt=1
                        success=false
                        while [ $attempt -le $max_attempts ]; do
                            echo "Attempt $attempt of $max_attempts to set the tier..."
                            if aios-cli hive select-tier $tier 2>&1 | grep -q "Failed"; then
                                echo "Attempt $attempt failed"
                                sleep 5
                            else
                                success=true
                                break
                            fi
                            attempt=$((attempt + 1))
                        done
                        if [ "$success" = true ]; then
                            echo "Tier $tier successfully set"
                            echo "Connection status:"
                            aios-cli hive whoami
                        else
                            echo "Error setting tier"
                            source /root/.bashrc
                            sleep 2
                            aios-cli hive login
                            sleep 2
                            aios-cli hive select-tier $tier
                            echo "Node processes:"
                            ps aux | grep "[a]ios"
                            tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Logs not found"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    3)
                        echo "Adding a model..."
                        echo "Adding model ${MODEL}..."
                        aios-cli models add "$MODEL"
                        echo "Active models:"
                        aios-cli models list
                        model_short=$(echo $MODEL | cut -d: -f2)
                        if aios-cli models list | grep -q "${model_short}"; then
                            echo "Model ${model_short} added successfully"
                        else
                            echo "Error: Model not found in active list"
                            echo "Try adding again"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    4)
                        echo "Connecting to Hive..."
                        echo "1. Stopping processes..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        echo "2. Starting the node..."
                        echo "Enter your private key:"
                        read private_key
                        echo "$private_key" > my.pem
                        chmod 600 my.pem
                        echo "Importing keys..."
                        aios-cli hive import-keys ./my.pem
                        sleep 2
                        echo "Logging in..."
                        aios-cli hive login
                        sleep 2
                        echo "Setting tier to 3..."
                        aios-cli hive select-tier 3
                        sleep 2
                        echo "Starting in screen..."
                        screen -dmS Hypernodes aios-cli start
                        sleep 2
                        echo "Adding model ${MODEL}..."
                        aios-cli models add "$MODEL"
                        sleep 2
                        echo "Connecting to Hive..."
                        aios-cli hive connect
                        sleep 5
                        if aios-cli hive whoami | grep -q "Public:"; then
                            echo "Node ready to work"
                        else
                            echo "Error connecting"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    5)
                        echo "Checking earned points..."
                        aios-cli hive points
                        echo "Press Enter to continue..."
                        read
                        ;;
                    6)
                        echo "Model Management:"
                        echo "Active models:"
                        aios-cli models list
                        echo "Available models:"
                        aios-cli models available
                        echo "Press Enter to continue..."
                        read
                        ;;
                    7)
                        echo "Checking connection status..."
                        echo "Connection:"
                        aios-cli hive whoami
                        echo "Points:"
                        aios-cli hive points
                        echo "Available models:"
                        aios-cli models available
                        echo "Press Enter to continue..."
                        read
                        ;;
                    8)
                        echo "Stopping the node..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        if pgrep -f "aios" > /dev/null; then
                            echo "Unable to stop all processes"
                            ps aux | grep "[a]ios"
                        else
                            echo "Node successfully stopped"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    9)
                        echo "Performing full restart with cleanup..."
                        echo "Stopping processes..."
                        aios-cli kill
                        pkill -f "aios"
                        sleep 2
                        echo "Restarting environment..."
                        source /root/.bashrc
                        sleep 2
                        echo "Starting node..."
                        aios-cli start
                        sleep 5
                        echo "Logging in..."
                        aios-cli hive login
                        sleep 2
                        echo "Setting tier 3..."
                        aios-cli hive select-tier 3
                        sleep 2
                        echo "Adding model ${MODEL}..."
                        aios-cli models add "$MODEL"
                        sleep 2
                        echo "Connecting to Hive..."
                        aios-cli hive connect
                        echo "Connection status:"
                        aios-cli hive whoami
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
            echo "This action will delete only files and settings of the Hyperspace Node."
            echo "Other installed nodes will not be affected."
            echo -n "Are you sure? (y/N): "
            read confirm
            if [[ $confirm == "y" || $confirm == "Y" ]]; then
                echo "Stopping the Hyperspace node..."
                aios-cli kill
                echo "Deleting node files..."
                if [ -d ~/.aios ]; then
                    echo "Found ~/.aios directory"
                    echo -n "Delete ~/.aios? (y/N): "
                    read confirm_aios
                    if [[ $confirm_aios == "y" || $confirm_aios == "Y" ]]; then
                        rm -rf ~/.aios
                        echo "Directory ~/.aios deleted"
                    fi
                fi
                if [ -f my.pem ]; then
                    echo -n "Delete file my.pem? (y/N): "
                    read confirm_pem
                    if [[ $confirm_pem == "y" || $confirm_pem == "Y" ]]; then
                        rm -f my.pem
                        echo "File my.pem deleted"
                    fi
                fi
                echo "Deleting installed packages..."
                echo "To completely delete packages, run:"
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
            show_resource_usage
            ;;
        7)
            echo "Thank you for using the installer!"
            echo "Don't forget to subscribe to @nodetrip on Telegram"
            exit 0
            ;;
    esac
done

while true; do
    check_connection
    sleep 300
done &
