#!/bin/bash

# Функция для отображения заголовка
show_header() {
    clear
    echo "==============================================="
    echo "    Установка и настройка Hyperspace Node"
    echo "==============================================="
    echo "Подпишитесь на наш Telegram канал @nodetrip"
    echo "для получения последних обновлений и поддержки"
    echo "==============================================="
    echo
}

# Функция для отображения инструкции
show_instructions() {
    show_header
    echo "Простая установка Hyperspace Node:"
    echo "1. Установите ноду"
    echo "2. Вставьте ваш приватный ключ"
    echo "3. Выберите tier в зависимости от RAM"
    echo "   (tier 3 для RAM > 8GB, tier 5 для RAM < 8GB)"
    echo "4. Дождитесь начисления первых поинтов (~30-60 минут)"
    echo
    echo "Нажмите Enter для продолжения..."
    read
}

# Основное меню
show_menu() {
    show_header
    echo "Выберите действие:"
    echo "1. Установить Hyperspace Node"
    echo "2. Управление нодой"
    echo "3. Проверка статуса"
    echo "4. Удалить ноду"
    echo "5. Показать инструкцию"
    echo "6. Выход"
    echo
    echo -n "Ваш выбор (1-6): "
}

# Подменю управления нодой
node_menu() {
    show_header
    if ! check_installation; then
        echo "Ошибка: aios-cli не установлен. Сначала выполните установку (пункт 1)"
        echo "Нажмите Enter для продолжения..."
        read
        return
    fi
    echo "Управление нодой:"
    echo "1. Запустить ноду"
    echo "2. Выбрать tier"
    echo "3. Добавить модель по умолчанию"
    echo "4. Подключиться к Hive"
    echo "5. Проверить заработанные поинты"
    echo "6. Управление моделями"
    echo "7. Проверить статус подключения"
    echo "8. Остановить ноду"
    echo "9. Перезапуск с очисткой"
    echo "10. Вернуться в главное меню"
    echo
    echo -n "Ваш выбор (1-10): "
}

# Функция установки и настройки ключей
setup_keys() {
    # Проверяем существующие ключи
    if [ -f my.pem ]; then
        echo "Обнаружен существующий файл ключа."
        echo -n "Хотите использовать новый ключ? (y/N): "
        read replace_key
        if [[ $replace_key != "y" && $replace_key != "Y" ]]; then
            echo "Продолжаем использовать существующий ключ."
            return
        fi
    fi

    echo "Введите приватный ключ:"
    read private_key
    
    # Очищаем ключ от лишних символов
    private_key=$(echo "$private_key" | tr -d '[:space:]')
    
    # Сохраняем ключ
    echo "$private_key" > my.pem
    chmod 600 my.pem
    
    # Проверяем содержимое файла
    echo "Проверка сохраненного ключа:"
    hexdump -C my.pem
    
    if command -v aios-cli &> /dev/null; then
        # Останавливаем все процессы
        echo "Останавливаем старые процессы..."
        aios-cli kill
        pkill -f "aios"
        
        # Закрываем все screen сессии
        echo "Закрываем screen сессии..."
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        # Сохраняем бинарный файл
        if [ -f ~/.aios/aios-cli ]; then
            mv ~/.aios/aios-cli /tmp/
        fi
        rm -rf ~/.aios/*
        mkdir -p ~/.aios
        if [ -f /tmp/aios-cli ]; then
            mv /tmp/aios-cli ~/.aios/
        fi
        
        # Переустанавливаем
        echo "Переустанавливаем aios-cli..."
        curl https://download.hyper.space/api/install | bash
        source /root/.bashrc
        sleep 5
        
        # Закрываем все screen сессии
        echo "Закрываем screen сессии..."
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        # Запускаем демон в screen с логированием
        echo "Запускаем aios-cli..."
        screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
        sleep 10
        
        # Проверяем что процесс запущен
        if ! ps aux | grep -q "[_]aios-kernel"; then
            echo "Ошибка: процесс не запущен"
            echo "Проверяем логи демона..."
            tail -n 50 ~/.aios/screen.log
            return 1
        fi
        
        # Сначала импортируем ключ
        echo "Импортируем ключ..."
        aios-cli hive import-keys ./my.pem
        sleep 5
        
        # Логинимся
        echo "Выполняем вход..."
        aios-cli hive login
        sleep 5
        
        # Проверяем что ключ импортирован
        if ! aios-cli hive whoami | grep -q "Public:"; then
            echo "Ошибка: ключ не импортирован"
            return 1
        fi
        
        # Подключаемся к Hive
        echo "Подключаемся к Hive..."
        aios-cli hive connect
        sleep 10
        
        # Устанавливаем tier
        echo "Устанавливаем tier..."
        aios-cli hive select-tier 5
        sleep 10
        
        # Проверяем tier
        if ! aios-cli hive points | grep -q "Tier: 5"; then
            echo "Ошибка: не удалось установить tier"
            return 1
        fi
        
        # Добавляем модель
        echo "Добавляем модель..."
        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
        sleep 10
        
        # Проверяем что модель скачалась
        echo "Проверяем статус модели..."
        if ! aios-cli models list | grep -q "phi-2"; then
            echo "Ожидаем загрузку модели..."
            for i in {1..12}; do  # Ждем максимум 2 минуты
                if aios-cli models list | grep -q "phi-2"; then
                    break
                fi
                echo -n "."
                sleep 10
            done
        fi
        
        # Проверяем что модель инициализирована
        echo "Проверяем инициализацию модели..."
        if ! grep -q "llm_load_print_meta: model size" ~/.aios/screen.log; then
            echo "Ожидаем инициализацию модели..."
            for i in {1..6}; do  # Ждем максимум 1 минуту
                if grep -q "llm_load_print_meta: model size" ~/.aios/screen.log; then
                    break
                fi
                echo -n "."
                sleep 10
            done
        fi
        
        # Если модель не зарегистрирована, перезапускаем
        if aios-cli hive whoami | grep -q "Failed to register models"; then
            echo "Перезапускаем демон для регистрации модели..."
            aios-cli kill
            pkill -f "aios"
            sleep 3
            
            screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
            sleep 10
            
            # Проверяем что screen создался
            if ! screen -ls | grep -q "Hypernodes"; then
                echo "Ошибка: screen сессия не создана"
                return 1
            fi
            
            aios-cli hive connect
            sleep 5
            
            # Проверяем статус
            echo "Проверяем статус..."
            aios-cli hive whoami
            aios-cli models list
            
            # Финальная проверка
            if ! aios-cli hive whoami | grep -q "Successfully connected"; then
                echo "Ошибка: не удалось подключиться к Hive"
                return 1
            fi
            
            echo "✅ Нода успешно настроена и готова к работе!"
        fi
    else
        echo "Ошибка: aios-cli не найден"
    fi
}

# Функция проверки установки
check_installation() {
    if ! command -v aios-cli &> /dev/null; then
        echo "aios-cli не найден. Перезагружаем окружение..."
        export PATH="$PATH:/root/.aios"
        source /root/.bashrc
        
        if ! command -v aios-cli &> /dev/null; then
            return 1
        fi
    fi
    return 0
}

# Функция проверки статуса ноды
check_node_status() {
    echo "Проверка статуса ноды..."
    
    # Проверяем запущена ли нода
    if ! ps aux | grep -q "[_]aios-kernel"; then
        echo "❌ Нода не запущена"
        echo "Запускаем ноду..."
        
        # Останавливаем все процессы
        aios-cli kill
        pkill -f "aios"
        sleep 3
        
        # Закрываем все screen сессии
        screen -ls | grep Hypernodes | cut -d. -f1 | awk '{print $1}' | xargs -I % screen -X -S % quit
        sleep 2
        
        # Запускаем демон
        screen -L -Logfile ~/.aios/screen.log -dmS Hypernodes aios-cli start
        sleep 10
        
        # Проверяем что процесс запущен
        if ! ps aux | grep -q "[_]aios-kernel"; then
            echo "Ошибка: не удалось запустить ноду"
            return 1
        fi
        
        # Логинимся
        echo "Выполняем вход..."
        aios-cli hive login
        sleep 5
    fi
    
    # Проверяем и восстанавливаем подключение к Hive
    echo "Проверяем подключение к Hive..."
    max_attempts=3
    attempt=1
    connected=false
    
    while [ $attempt -le $max_attempts ]; do
        if aios-cli hive whoami 2>&1 | grep -q "Public:"; then
            connected=true
            echo "✅ Успешно подключились к Hive"
            break
        fi
        echo "Попытка $attempt из $max_attempts подключиться к Hive..."
        aios-cli hive connect
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ "$connected" = false ]; then
        echo "❌ Не удалось подключиться к Hive после $max_attempts попыток"
        echo "Пробуем перезапустить ноду..."
        aios-cli kill
        sleep 5
        screen -dmS Hypernodes aios-cli start
        sleep 10
        aios-cli hive login
        sleep 5
        aios-cli hive connect
    fi
    
    # Проверяем статус
    echo "1. Проверка ключей:"
    aios-cli hive whoami
    
    echo "2. Проверка points:"
    if ! aios-cli hive points; then
        echo "Ошибка получения points, проверьте подключение к Hive"
        echo "Пробуем восстановить подключение..."
        aios-cli hive login
        sleep 5
        aios-cli hive connect
        sleep 5
        echo "Повторная проверка points..."
        aios-cli hive points
    fi
    
    echo "3. Проверка моделей:"
    echo "Активные модели:"
    aios-cli models list
    echo
    echo "Доступные модели:"
    aios-cli models available
    
    return 0
}

# Функция диагностики
diagnose_installation() {
    echo "=== Диагностика установки ==="
    echo "1. Проверка путей:"
    echo "PATH=$PATH"
    echo
    echo "2. Проверка бинарного файла:"
    ls -l /root/.aios/aios-cli
    echo
    echo "3. Проверка версии:"
    /root/.aios/aios-cli hive version
    echo
    echo "4. Проверка конфигурации:"
    ls -la ~/.aios/
    echo
    echo "5. Проверка подключения к сети:"
    curl -Is https://download.hyper.space | head -1
    echo
    echo "6. Проверка статуса службы:"
    ps aux | grep aios-cli
    echo
    echo "7. Проверка логов:"
    tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Логи не найдены"
    echo
    echo "=== Конец диагностики ==="
}

# Функция проверки запущенной ноды
check_node_running() {
    if pgrep -f "__aios-kernel" >/dev/null || pgrep -f "aios-cli start" >/dev/null; then
        echo "Нода уже запущена"
        ps aux | grep -E "aios-cli|__aios-kernel" | grep -v grep
        return 0
    fi
    return 1
}

# Функция проверки и восстановления подключения
check_connection() {
    echo "Проверка подключения к Hive..."
    if ! aios-cli hive whoami | grep -q "Public:"; then
        echo "❌ Потеряно подключение к Hive"
        echo "Пробуем восстановить..."
        
        # Останавливаем процессы
        aios-cli kill
        pkill -f "aios"
        sleep 3
        
        # Перезапускаем демон
        screen -dmS Hypernodes aios-cli start
        sleep 10
        
        # Переподключаемся
        aios-cli hive login
        sleep 5
        aios-cli hive connect
        sleep 5
        
        if aios-cli hive whoami | grep -q "Public:"; then
            echo "✅ Подключение восстановлено"
            return 0
        else
            echo "❌ Не удалось восстановить подключение"
            return 1
        fi
    else
        echo "✅ Подключение активно"
        return 0
    fi
}

# Основная логика
while true; do
    show_menu
    read choice
    case $choice in
        1)
            show_header
            echo "Установка Hyperspace Node..."
            curl https://download.hyper.space/api/install | bash
            
            # Перезагружаем окружение
            # Проверяем, не добавлен ли уже путь
            if ! echo $PATH | grep -q "/root/.aios"; then
                export PATH="$PATH:/root/.aios"
            fi
            source /root/.bashrc
            
            # Автоматическая настройка ключей после установки
            echo "Подождите 5 секунд, пока система инициализируется..."
            sleep 5
            
            if ! command -v aios-cli &> /dev/null; then
                echo "Ошибка: aios-cli не установлен корректно."
                echo "Попробуйте выполнить следующие команды вручную:"
                echo "1. source /root/.bashrc"
                echo "2. aios-cli hive import-keys ./my.pem"
                echo "Нажмите Enter для продолжения..."
                read
                continue
            fi
            
            setup_keys
            
            echo "Установка завершена. Нажмите Enter для продолжения..."
            read
            ;;
        2)
            while true; do
                node_menu
                read node_choice
                case $node_choice in
                    1)
                        echo "Очистка старых сессий..."
                        if check_node_running; then
                            echo "Нода уже работает. Хотите перезапустить? (y/N): "
                            read restart
                            if [[ $restart != "y" && $restart != "Y" ]]; then
                                echo "Отмена запуска"
                                return
                            fi
                        fi
                        # Сначала останавливаем существующие процессы
                        echo "Останавливаем существующие процессы..."
                        pkill -f "__aios-kernel" || true
                        pkill -f "aios-cli start" || true
                        sleep 2
                        
                        # Находим и закрываем все сессии Hypernodes
                        screen -ls | grep Hypernodes | cut -d. -f1 | while read pid; do
                            echo "Закрываем сессию с PID: $pid"
                            kill $pid 2>/dev/null || true
                        done
                        sleep 2
                        
                        # Исправляем PATH
                        export PATH="/root/.aios:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                        
                        echo "Запускаем ноду..."
                        echo "Запуск в screen..."
                        screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                        echo "Ожидание запуска ноды..."
                        start_time=$(date +%s)
                        timeout=300  # 5 минут таймаут
                        
                        while true; do
                            current_time=$(date +%s)
                            elapsed=$((current_time - start_time))
                            
                            # Проверяем процессы
                            if ps aux | grep -q "[_]aios-kernel"; then
                                if aios-cli hive whoami | grep -q "Public"; then
                                    echo "✅ Нода успешно запущена и подключена"
                                    break
                                fi
                            fi
                            
                            # Проверяем таймаут
                            if [ $elapsed -gt $timeout ]; then
                                echo "❌ Превышен таймаут запуска"
                                echo "Перезапускаем ноду..."
                                pkill -9 -f "aios"
                                sleep 2
                                screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                                sleep 5
                                break
                            fi
                            
                            echo -n "."
                            sleep 5
                        done
                        
                        # Проверяем, запустилась ли нода
                        if screen -ls | grep -q "Hypernodes"; then
                            echo "Нода успешно запущена"
                            # Проверяем процесс
                            ps aux | grep "[a]ios-cli"
                            echo "Проверка лога запуска..."
                            screen -r Hypernodes -X hardcopy .screen.log
                            echo "Последние логи:"
                            tail -n 5 .screen.log
                        else
                            echo "Ошибка: Нода не запустилась"
                            echo "Проверка окружения:"
                            echo "PATH=$PATH"
                            echo "Проверка процессов:"
                            ps aux | grep "[a]ios"
                            echo "Пробуем альтернативный способ запуска..."
                            screen -dmS Hypernodes bash -c "source /root/.bashrc && aios-cli start"
                            sleep 5
                            if screen -ls | grep -q "Hypernodes"; then
                                echo "Нода запущена альтернативным способом"
                                ps aux | grep "[a]ios-cli"
                            else
                                echo "Ошибка: Не удалось запустить ноду"
                                echo "Последние ошибки:"
                                tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Логи не найдены"
                            fi
                        fi
                        echo "Нода запущена в screen сессии 'Hypernodes'"
                        echo "Чтобы посмотреть логи, используйте команду: screen -r Hypernodes"
                        echo "Для выхода из логов нажмите Ctrl+A, затем D"
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    2)
                        # Сначала проверяем статус ноды и подключения
                        echo "Проверка статуса перед установкой tier..."
                        echo "1. Проверка процессов:"
                        ps aux | grep "[a]ios"
                        echo
                        echo "2. Проверка подключения:"
                        if ! aios-cli hive whoami | grep -q "Public:"; then
                            echo "❌ Нода не подключена к Hive"
                            echo "Сначала выполните вход:"
                            aios-cli hive login
                            sleep 2
                        fi
                        
                        echo "Выберите tier (3 для RAM > 8GB, 5 для RAM < 8GB):"
                        echo "Рекомендации по tier:"
                        echo "- Tier 5: для легких моделей (phi-2 ~1.67GB)"
                        echo "- Tier 3: для тяжелых моделей (>8GB RAM)"
                        read tier
                        echo "Устанавливаем tier $tier..."
                        # Пробуем несколько раз
                        max_attempts=3
                        attempt=1
                        success=false
                        while [ $attempt -le $max_attempts ]; do
                            echo "Попытка установки tier $attempt из $max_attempts..."
                            if aios-cli hive select-tier $tier 2>&1 | grep -q "Failed"; then
                                echo "❌ Попытка $attempt не удалась"
                                sleep 5
                            else
                                success=true
                                break
                            fi
                            attempt=$((attempt + 1))
                        done
                        
                        if [ "$success" = true ]; then
                            echo "✅ Tier $tier успешно установлен"
                            echo "Проверяем подключение:"
                            aios-cli hive whoami
                        else
                            echo "❌ Ошибка при установке tier"
                            echo "Пробуем альтернативный способ..."
                            echo "1. Перезапускаем окружение"
                            source /root/.bashrc
                            sleep 2
                            echo "2. Проверяем login"
                            aios-cli hive login
                            sleep 2
                            echo "3. Пробуем установить tier снова"
                            aios-cli hive select-tier $tier
                            echo "Проверяем статус ноды:"
                            ps aux | grep "[a]ios"
                            echo
                            echo "Проверяем логи:"
                            tail -n 20 ~/.aios/logs/* 2>/dev/null || echo "Логи не найдены"
                        fi
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    3)
                        echo "Добавляем модель по умолчанию..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        echo
                        echo "Проверяем активные модели:"
                        aios-cli models list
                        echo
                        if aios-cli models list | grep -q "phi-2"; then
                            echo "✅ Модель phi-2 успешно добавлена"
                        else
                            echo "❌ Ошибка: Модель не найдена в списке активных"
                            echo "Попробуйте добавить модель снова"
                        fi
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    4)
                        echo "Подключаемся к Hive..."
                        echo "1. Останавливаем текущие процессы..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        
                        echo "2. Запускаем ноду заново..."
                        echo "Проверяем ключи..."
                        
                        echo "Введите приватный ключ:"
                        read private_key
                        echo "$private_key" > my.pem
                        chmod 600 my.pem
                        
                        echo "Импортируем ключи..."
                        aios-cli hive import-keys ./my.pem
                        sleep 2
                        
                        echo "Выполняем вход..."
                        aios-cli hive login
                        sleep 2
                        
                        echo "Устанавливаем tier 5..."
                        aios-cli hive select-tier 5
                        sleep 2
                        
                        echo "Запускаем в screen..."
                        screen -dmS Hypernodes aios-cli start
                        sleep 2
                        
                        echo "Добавляем модель phi-2..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        sleep 2
                        
                        echo "Подключаемся к Hive..."
                        aios-cli hive connect
                        sleep 5
                        
                        echo "Проверяем статус ноды..."
                        if aios-cli hive whoami | grep -q "Public:"; then
                            echo "✅ Нода готова к работе"
                        else
                            echo "❌ Ошибка подключения"
                        fi
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    5)
                        echo "Проверка заработанных поинтов..."
                        aios-cli hive points
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    6)
                        echo "Управление моделями:"
                        echo "1. Активные модели:"
                        aios-cli models list
                        echo
                        echo "2. Доступные модели:"
                        aios-cli models available
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    7)
                        echo "Проверка статуса подключения..."
                        echo "1. Статус подключения:"
                        aios-cli hive whoami
                        echo
                        echo "2. Проверка points:"
                        aios-cli hive points
                        echo
                        echo "3. Проверка моделей:"
                        aios-cli models available
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    8)
                        echo "Останавливаем ноду..."
                        aios-cli kill
                        pkill -9 -f "aios"
                        sleep 2
                        
                        # Проверяем, остановились ли процессы
                        if pgrep -f "aios" > /dev/null; then
                            echo "❌ Не удалось остановить все процессы"
                            echo "Активные процессы:"
                            ps aux | grep "[a]ios"
                        else
                            echo "✅ Нода успешно остановлена"
                        fi
                        echo "Нажмите Enter для продолжения..."
                        read
                        ;;
                    9)
                        echo "Выполняем полный перезапуск с очисткой..."
                        echo "1. Останавливаем все процессы..."
                        aios-cli kill
                        pkill -f "aios"
                        sleep 2
                        
                        echo "2. Перезагружаем окружение..."
                        source /root/.bashrc
                        sleep 2
                        
                        echo "3. Запускаем ноду..."
                        aios-cli start
                        sleep 5
                        
                        echo "4. Выполняем вход..."
                        aios-cli hive login
                        sleep 2
                        
                        echo "5. Устанавливаем tier 3..."
                        aios-cli hive select-tier 3
                        sleep 2
                        
                        echo "6. Добавляем модель phi-2..."
                        aios-cli models add hf:TheBloke/phi-2-GGUF:phi-2.Q4_K_M.gguf
                        sleep 2
                        
                        echo "7. Подключаемся к Hive..."
                        aios-cli hive connect
                        
                        echo "8. Проверяем статус..."
                        echo "Статус подключения:"
                        aios-cli hive whoami
                        echo
                        echo "Активные модели:"
                        aios-cli models list
                        
                        echo "Нажмите Enter для продолжения..."
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
            echo "Нажмите Enter для продолжения..."
            read
            ;;
        4)
            show_header
            echo "Внимание! Вы собираетесь удалить ноду Hyperspace."
            echo "Это действие удалит только файлы и настройки Hyperspace Node."
            echo "Другие установленные ноды не будут затронуты."
            echo
            echo -n "Вы уверены? (y/N): "
            read confirm
            if [[ $confirm == "y" || $confirm == "Y" ]]; then
                echo "Останавливаем Hyperspace ноду..."
                aios-cli kill
                echo "Удаляем файлы Hyperspace ноды..."
                if [ -d ~/.aios ]; then
                    echo "Найдена директория ~/.aios"
                    echo -n "Удалить ~/.aios? (y/N): "
                    read confirm_aios
                    if [[ $confirm_aios == "y" || $confirm_aios == "Y" ]]; then
                        rm -rf ~/.aios
                        echo "Директория ~/.aios удалена"
                    fi
                fi
                
                if [ -f my.pem ]; then
                    echo -n "Удалить файл my.pem? (y/N): "
                    read confirm_pem
                    if [[ $confirm_pem == "y" || $confirm_pem == "Y" ]]; then
                        rm -f my.pem
                        echo "Файл my.pem удален"
                    fi
                fi
                
                echo "Удаляем установленные пакеты..."
                echo "Для полного удаления пакетов выполните команду:"
                echo "apt remove aios-cli (если установлено через apt)"
                echo "Нода успешно удалена."
                echo "Нажмите Enter для продолжения..."
                read
            else
                echo "Отмена удаления."
                echo "Нажмите Enter для продолжения..."
                read
            fi
            ;;
        5)
            show_instructions
            ;;
        6)
            echo "Спасибо за использование установщика!"
            echo "Не забудьте подписаться на @nodetrip в Telegram"
            exit 0
            ;;
    esac
done

# Добавляем проверку в основной цикл
while true; do
    check_connection
    sleep 300 # Проверяем каждые 5 минут
done & 
