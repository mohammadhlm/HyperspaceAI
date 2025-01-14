# Function to show the header
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

# Function to show instructions
show_instructions() {
    show_header
    echo "Simple installation of Hyperspace Node:"
    echo "1. Install the node"
    echo "2. Insert your private key"
    echo "3. Choose a tier based on RAM"
    echo "   (tier 3 for RAM > 8GB, tier 5 for RAM < 8GB)"
    echo "4. Wait for the first points to be credited (~30-60 minutes)"
    echo
    echo "Press Enter to continue..."
    read
}

# Main menu
show_menu() {
    show_header
    echo "Choose an action:"
    echo "1. Install Hyperspace Node"
    echo "2. Manage node"
    echo "3. Check status"
    echo "4. Remove node"
    echo "5. Show instructions"
    echo "6. Exit"
    echo
    echo -n "Your choice (1-6): "
}

# Node management submenu
node_menu() {
    show_header
    if ! check_installation; then
        echo "Error: aios-cli is not installed. Please perform the installation first (item 1)"
        echo "Press Enter to continue..."
        read
        return
    fi
    echo "Node management:"
    echo "1. Start node"
    echo "2. Select tier"
    echo "3. Add default model"
    echo "4. Connect to Hive"
    echo "5. Check earned points"
    echo "6. Manage models"
    echo "7. Check connection status"
    echo "8. Stop node"
    echo "9. Restart with cleanup"
    echo "10. Return to main menu"
    echo
    echo -n "Your choice (1-10): "
}

# Function to set up and configure keys
setup_keys() {
    # Check for existing keys
    if [ -f my.pem ]; then
        echo "An existing key file was found."
        echo -n "Do you want to use a new key? (y/N): "
        read replace_key
        if [[ $replace_key != "y" && $replace_key != "Y" ]]; then
            echo "Continuing to use the existing key."
            return
        fi
    fi

    echo "Enter private key:"
    read private_key
    
    # Remove unnecessary characters from the key
    private_key=$(echo "$private_key" | tr -d '[:space:]')
    
    # Save the key
    echo "$private_key" > my.pem
    chmod 600 my.pem
    
    # Check the file contents
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
        
        # Start daemon in screen with logging
        echo "Starting aios-cli..."
        screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
        sleep 10
        
        # Check if the process is running
        if ! ps aux | grep -q "[_]aios-kernel"; then
            echo "Error: process is not running"
            echo "Checking daemon logs..."
            tail -n 50 ~/.aios/screen.log
            return 1
        fi
        
        # First, import the key
        echo "Importing key..."
        aios-cli hive import-keys ./my.pem
        sleep 5
        
        # Log in
        echo "Logging in..."
        aios-cli hive login
        sleep 5
        
        # Check that the key is imported
        if ! aios-cli hive whoami | grep -q "Public:"; then
            echo "Error: key not imported"
            return 1
        fi
        
        # Connect to Hive
        echo "Connecting to Hive..."
        aios-cli hive connect
        sleep 10
        
        # Set tier
        echo "Setting tier..."
        aios-cli hive select-tier 5
        sleep 10
        
        # Check tier
        if ! aios-cli hive points | grep -q "Tier: 5"; then
            echo "Error: failed to set tier"
            return 1
        fi
        
        # Add model
        echo "Adding model..."
        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
        sleep 10
        
        # Check that model downloaded
        echo "Checking model status..."
        if ! aios-cli models list | grep -q "phi-2"; then
            echo "Waiting for the model to load..."
            for i in {1..12}; do  # Wait a maximum of 2 minutes
                if aios-cli models list | grep -q "phi-2"; then
                    break
                fi
                echo -n "."
                sleep 10
            done
        fi
        
        # Check if the model is initialized
        echo "Checking model initialization..."
        if ! grep -q "llm_load_print_meta: model size" ~/.aios/screen.log; then
            echo "Waiting for the model to initialize..."
            for i in {1..6}; do  # Wait a maximum of 1 minute
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
            
            # Check that the screen was created
            if ! screen -ls | grep -q "Hypernodes"; then
                echo "Error: screen session not created"
                return 1
            fi
            
            aios-cli hive connect
            sleep 5
            
            # Check status
            echo "Checking status..."
            aios-cli hive whoami
            aios-cli models list
            
            # Final check
            if ! aios-cli hive whoami | grep -q "Successfully connected"; then
                echo "Error: failed to connect to Hive"
                return 1
            fi
            
            echo "✅ Node successfully configured and ready to work!"
        fi
    else
        echo "Error: aios-cli not found"
    fi
}

# Function to check installation
check_installation() {
    if ! command -v aios-cli &> /dev/null; then
        echo "aios-cli not found. Reloading environment..."
        export PATH="$PATH:/root/.aios"
        source /root/.bashrc
        
        if ! command -v aios-cli &> /dev/null; then
            return 1
        fi
    fi
    return 0
}

# Function to check node status
check_node_status() {
    echo "Checking node status..."
    
    # Check if the node is running
    if ! ps aux | grep -q "[_]aios-kernel"; then
        echo "❌ Node is not running"
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
            echo "Error: failed to start the node"
            return 1
        fi
        
        # Log in
        echo "Logging in..."
        aios-cli hive login
        sleep 5
    fi
    
    # Check and restore connection to Hive
    echo "Checking connection to Hive..."
    max_attempts=3
    attempt=1
    connected=false
    
    while [ $attempt -le $max_attempts ]; do
        if aios-cli hive whoami 2>&1 | grep -q "Public:"; then
            connected=true
            echo "✅ Successfully connected to Hive"
            break
        fi
        echo "Attempt $attempt of $max_attempts to connect to Hive..."
        aios-cli hive connect
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ "$connected" = false ]; then
        echo "❌ Failed to connect to Hive after $max_attempts attempts"
        echo "Trying to restart the node..."
        aios-cli kill
        sleep 5
        screen -dmS Hypernodes aios-cli start
        sleep 10
        aios-cli hive login
        sleep 5
        aios-cli hive connect
    fi
    
    # Check status
    echo "1. Checking keys:"
    aios-cli hive whoami
    
    echo "2. Checking points:"
    if ! aios-cli hive points; then
        echo "Error obtaining points, check connection to Hive"
        echo "Trying to restore connection..."
        aios-cli hive login
        sleep 5
        aios-cli hive connect
        sleep 5
        echo "Rechecking points..."
        aios-cli hive points
    fi
    
    echo "3. Checking models:"
    echo "Active models:"
    aios-cli models list
    echo
    echo "Available models:"
    aios-cli models available
    
    return 0
}

# Diagnostic function
diagnose_installation() {
    echo "=== Installation Diagnostics ==="
    echo "1. Checking paths:"
    echo "PATH=$PATH"
    echo
    echo "2. Checking binary file:"
    ls -l /root/.aios/aios-cli
    echo
    echo "3. Checking version:"
    /root/.aios/aios-cli hive version
    echo
    echo "4. Checking configuration:"
    ls -la ~/.aios/
    echo
    echo "5. Checking network connection:"
    curl -Is https://download.hyper.space | head -1
    echo
    echo "6. Checking service status:"
    ps aux | grep aios-cli
    echo
    echo "7. Checking logs:"
    tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Logs not found"
    echo
    echo "=== End of diagnostics ==="
}

# Check if node is running
check_node_running() {
    if pgrep -f "__aios-kernel" >/dev/null || pgrep -f "aios-cli start" >/dev/null; then
        echo "Node is already running"
        ps aux | grep -E "aios-cli|__aios-kernel" | grep -v grep
        return 0
    fi
    return 1
}

# Check and restore connection
check_connection() {
    echo "Checking connection to Hive..."
    if ! aios-cli hive whoami | grep -q "Public:"; then
        echo "❌ Lost connection to Hive"
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
            echo "✅ Connection restored"
            return 0
        else
            echo "❌ Failed to restore connection"
            return 1
        fi
    else
        echo "✅ Connection is active"
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
            
            # Reload environment
            # Check if the path has been added already
            if ! echo $PATH | grep -q "/root/.aios"; then
                export PATH="$PATH:/root/.aios"
            fi
            source /root/.bashrc
            
            # Automatic setup of keys after installation
            echo "Please wait 5 seconds while the system initializes..."
            sleep 5
            
            if ! command -v aios-cli &> /dev/null; then
                echo "Error: aios-cli is not installed correctly."
                echo "Try running the following commands manually:"
                echo "1. source /root/.bashrc"
                echo "2. aios-cli hive import-keys ./my.pem"
                echo "Press Enter to continue..."
                read
                continue
            fi
            
            setup_keys
            
            echo "Installation completed. Press Enter to continue..."
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
                            echo "Node is already running. Do you want to restart? (y/N): "
                            read restart
                            if [[ $restart != "y" && $restart != "Y" ]]; then
                                echo "Cancelling start"
                                return
                            fi
                        fi
                        # First, stop existing processes
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
                        
                        # Fix PATH
                        export PATH="/root/.aios:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                        
                        echo "Starting the node..."
                        echo "Starting in screen..."
                        screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                        echo "Waiting for the node to start..."
                        start_time=$(date +%s)
                        timeout=300  # 5 minutes timeout
                        
                        while true; do
                            current_time=$(date +%s)
                            elapsed=$((current_time - start_time))
                            
                            # Check processes
                            if ps aux | grep -q "[_]aios-kernel"; then
                                if aios-cli hive whoami | grep -q "Public"; then
                                    echo "✅ Node successfully started and connected"
                                    break
                                fi
                            fi
                            
                            # Check timeout
                            if [ $elapsed -gt $timeout ]; then
                                echo "❌ Start timeout exceeded"
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
                            # Check process
                            ps aux | grep "[a]ios-cli"
                            echo "Checking start log..."
                            screen -r Hypernodes -X hardcopy .screen.log
                            echo "Latest logs:"
                            tail -n 5 .screen.log
                        else
                            echo "Error: Node did not start"
                            echo "Checking environment:"
                            echo "PATH=$PATH"
                            echo "Checking processes:"
                            ps aux | grep "[a]ios"
                            echo "Trying an alternative way to start..."
                            screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                            sleep 5
                            if screen -ls | grep -q "Hypernodes"; then
                                echo "Node started in an alternative way"
                                ps aux | grep "[a]ios-cli"
                            else
                                echo "Error: Failed to start the node"
                                echo "Latest errors:"
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
                        # First, check the status of the node and connection
                        echo "Checking status before setting tier..."
                        echo "1. Checking processes:"
                        ps aux | grep "[a]ios"
                        echo
                        echo "2. Checking connection:"
                        if ! aios-cli hive whoami | grep -q "Public:"; then
                            echo "❌ Node is not connected to Hive"
                            echo "Please log in first:"
                            aios-cli hive login
                            sleep 2
                        fi
                        
                        echo "Select tier (3 for RAM > 8GB, 5 for RAM < 8GB):"
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
                            echo "Attempting to set tier $attempt of $max_attempts..."
                            if aios-cli hive select-tier $tier 2>&1 | grep -q "Failed"; then
                                echo "❌ Attempt $attempt failed"
                                sleep 5
                            else
                                success=true
                                break
                            fi
                            attempt=$((attempt + 1))
                        done
                        
                        if [ "$success" = true ]; then
                            echo "✅ Tier $tier successfully set"
                            echo "Checking connection:"
                            aios-cli hive whoami
                        else
                            echo "❌ Error setting tier"
                            echo "Trying alternative method..."
                            echo "1. Restarting the environment"
                            source /root/.bashrc
                            sleep 2
                            echo "2. Checking login"
                            aios-cli hive login
                            sleep 2
                            echo "3. Trying to set tier again"
                            aios-cli hive select-tier $tier
                            echo "Checking node status:"
                            ps aux | grep "[a]ios"
                            echo
                            echo "Checking logs:"
                            tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Logs not found"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    3)
                        echo "Adding default model..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        echo
                        echo "Checking active models:"
                        aios-cli models list
                        echo
                        if aios-cli models list | grep -q "phi-2"; then
                            echo "✅ Model phi-2 successfully added"
                        else
                            echo "❌ Error: Model not found in the active list"
                            echo "Try adding the model again"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    4)
                        echo "Connecting to Hive..."
                        echo "1. Stopping current processes..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        
                        echo "2. Restarting the node..."
                        echo "Checking keys..."
                        
                        echo "Enter private key:"
                        read private_key
                        echo "$private_key" > my.pem
                        chmod 600 my.pem
                        
                        echo "Importing keys..."
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
                        
                        echo "Adding model phi-2..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        sleep 2
                        
                        echo "Connecting to Hive..."
                        aios-cli hive connect
                        sleep 5
                        
                        echo "Checking node status..."
                        if aios-cli hive whoami | grep -q "Public:"; then
                            echo "✅ Node ready to work"
                        else
                            echo "❌ Connection error"
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
                        echo "Managing models:"
                        echo "1. Active models:"
                        aios-cli models list
                        echo
                        echo "2. Available models:"
                        aios-cli models available
                        echo "Press Enter to continue..."
                        read
                        ;;
                    7)
                        echo "Checking connection status..."
                        echo "1. Connection status:"
                        aios-cli hive whoami
                        echo
                        echo "2. Checking points:"
                        aios-cli hive points
                        echo
                        echo "3. Checking models:"
                        aios-cli models available
                        echo "Press Enter to continue..."
                        read
                        ;;
                    8)
                        echo "Stopping the node..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        
                        # Check if processes stopped
                        if pgrep -f "aios" > /dev/null; then
                            echo "❌ Failed to stop all processes"
                            echo "Active processes:"
                            ps aux | grep "[a]ios"
                        else
                            echo "✅ Node successfully stopped"
                        fi
                        echo "Press Enter to continue..."
                        read
                        ;;
                    9)
                        echo "Executing full restart with cleanup..."
                        echo "1. Stopping all processes..."
                        aios-cli kill
                        pkill -f "aios"
                        sleep 2
                        
                        echo "2. Reloading environment..."
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
                        
                        echo "6. Adding model phi-2..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        sleep 2
                        
                        echo "7. Connecting to Hive..."
                        aios-cli hive connect
                        
                        echo "8. Checking status..."
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
            echo "Warning! You are about to remove the Hyperspace node."
            echo "This action will only delete the files and settings of the Hyperspace Node."
            echo "Other installed nodes will not be affected."
            echo
            echo -n "Are you sure? (y/N): "
            read confirm
            if [[ $confirm == "y" || $confirm == "Y" ]]; then
                echo "Stopping the Hyperspace node..."
                aios-cli kill
                echo "Removing Hyperspace node files..."
                if [ -d ~/.aios ]; then
                    echo "Directory ~/.aios found"
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
                
                echo "Removing installed packages..."
                echo "For complete removal of packages, execute the command:"
                echo "apt remove aios-cli (if installed via apt)"
                echo "Node successfully removed."
                echo "Press Enter to continue..."
                read
            else
                echo "Deletion cancelled."
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

# Add a check in the main loop
while true; do
    check_connection
    sleep 300 # Check every 5 minutes
done &
