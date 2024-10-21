#!/bin/bash

GITLAB="origin"
GITLAB_ADDR="192.168.122.69"
GITLAB_SSH="git@192.168.122.69:Biba/openvair.git"

echo $GITLAB
echo $GITLAB_ADDR
echo $GITLAB_SSH

GITHUB="github"
GITHUB_ADDR="github.com"
GITHUB_SSH="git@github.com:VladimirTrue/openvair.git"

echo $GITHUB
echo $GITHUB_ADDR
echo $GITHUB_SSH

echo 

whoami
pwd
cat ~/.ssh/id_rsa.pub
git remote show
echo

git branch -a

declare -A branch_status

log(){
    local operation=$1
    local status=$2
    local message=$3

    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # printf "%-6s: %-30s: %-20s: %s\n" "$status" "$(date)" "$operation" "$message"
    printf "[%s] - %-5s %-25s: %s\n" "$timestamp" "$status" "$operation" "$message"
    # printf '{"timestamp": "%s", "level": "%s", "operation": "%s", "message": "%s"}\n' \
    #     "$timestamp" "$level" "$operation" "$message"
    sleep 1
}

# Функция для добавления хоста в known_hosts
add_host_to_known_hosts() {
    local HOST=$1
    local operation="add_host_to_known_hosts"

    # Проверяем, существует ли хост в known_hosts
    if ! ssh-keygen -F "$HOST" &> /dev/null; then
        log $operation "INFO" "Хост $HOST не найден в known_hosts. Добавляем его..."
        ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts
        if [ $? -eq 0 ]; then
            log $operation "INFO" "Хост $HOST успешно добавлен в known_hosts."
        else
            log $operation "ERROR" "Ошибка при добавлении хоста $HOST в known_hosts."
        fi
    else
        log $operation "INFO" "Хост $HOST уже есть в known_hosts."
    fi
}

check_and_add_remote() {
    local REMOTE_NAME=$1
    local REMOTE_SSH=$2
    local operation="check_and_add_remote"

    # Проверяем, добавлен ли удалённый репозиторий
    if git remote get-url "$REMOTE_NAME" &> /dev/null; then
        log $operation "INFO" "Удалённый репозиторий '$REMOTE_NAME' уже добавлен."
    else
        log $operation "INFO" "Удалённый репозиторий '$REMOTE_NAME' не найден. Добавляем его..."
        git remote add "$REMOTE_NAME" "$REMOTE_SSH"
        if [ $? -eq 0 ]; then
            log $operation "INFO" "Удалённый репозиторий '$REMOTE_NAME' успешно добавлен."
        else
            log $operation "ERROR" "Ошибка при добавлении репозитория '$REMOTE_NAME'."
            return
        fi
    fi
}

fetch_all_remotes(){
    local operation="fetch_all_remotes"

    log $operation  "INFO" "Выполняю fetch всех репозиториев"
    if git fetch --all; then
        log $operation "INFO" "fetch прошёл успешно"
    else
        log $operation "ERROR" "Произошла ошибка при fetch"
    fi
    log $operation  "INFO" "fetch выполнен"
}

create_local_origin(){
    local REMOTE_NAME=$1
    local operation="create_local_origin"

    for branch in $(git branch -r | grep $REMOTE_NAME'/' | grep -v 'HEAD' | sed 's/'$REMOTE_NAME'\///'); do
        log $operation "INFO" "PROCCESS branch $branch for $REMOTE_NAME"
        if git rev-parse --verify $branch >/dev/null 2>&1; then
            log $operation "INFO" "SKIP: Local branch $branch already exists"
            branch_status["$branch,status"]="OK"
            branch_status["$branch,message"]="Not for merge"
        else
            if git checkout -b $branch $REMOTE_NAME/$branch; then
                log $operation "INFO" "$branch copied to local"
                branch_status["$branch,status"]="OK"
                branch_status["$branch,message"]="Branch copied to local"
            else
                log $operation "ERROR" "$branch not copied"
                branch_status["$branch,status"]="ERROR"
                branch_status["$branch,message"]="Failed to copy branch"
                continue
            fi
        fi
    done
}

merge_into_local(){
    local remote=$1
    local operation='merge_into_local'

    log $operation "INFO" "Merge remote branches from $remote, to local"
    for local_branch in $(git branch --list | sed 's/\*//'); do
        local remote_branch=$remote/$local_branch
    log $operation "INFO" "current remote branch $remote_branch, to local"
        if git checkout $local_branch; then
            # Проверка на дивергенцию ветки
            if git status | grep -q "have diverged"; then
                log $operation "ERROR" "Branch '$local_branch' and '$remote_branch' have diverged. Manual intervention required."
                branch_status["$local_branch,status"]="ERROR"
                branch_status["$local_branch,message"]="Branch diverged. Manual merge required."
                continue
            fi

            # проверка существует ли ветка в текущем удалённом репозитории
            if git branch -r | grep -q "$remote_branch"; then
                log $operation "INFO" "Remote branch '$local_branch' exists on '$remote'"

                log $operation "INFO" "merging $remote_branch to $local_branch"
                # выполнение мерджа
                if git merge $remote_branch; then
                    log $operation "INFO" "SUCCESS merging"
                    branch_status["$local_branch,status"]="OK"
                    branch_status["$local_branch,message"]="Successfully merged"
                else
                    log $operation "ERROR" "ERROR Нужно решить конфликт руками"
                    branch_status["$local_branch,status"]="ERROR"
                    branch_status["$local_branch,message"]="Manual merge required."

                    # Откатываем мердж для продолжения работы с другими ветками
                    log $operation "INFO" "Aborting merge due to conflict"
                    git merge --abort
                    continue
                fi
            else
                log $operation "INFO" "Remote branch '$local_branch' does not exist on '$remote'"
            fi
        else
            log $operation "ERROR" "ERROR while checkout to branch $local_branch"
            branch_status["$local_branch,status"]="ERROR"
            branch_status["$local_branch,message"]="Failed to checkout branch"
            continue
        fi
    done
}

check_for_errors() {
    local operation="check_for_errors"
    local error_found=false

    # Проходим по всем элементам массива branch_status
    for branch in "${!branch_status[@]}"; do
        # Отделяем название ветки от статуса
        branch_name="${branch%%,*}"
        branch_field="${branch##*,}"

        # Проверяем только статус ветки
        if [[ "$branch_field" == "status" && "${branch_status[$branch]}" == "ERROR" ]]; then
            log $operation "ERROR" "Branch: $branch_name - Status: ${branch_status[$branch_name,status]}, Message: ${branch_status[$branch_name,message]}"
            error_found=true
        fi
    done

    if [ "$error_found" = true ]; then
        log $operation "ERROR" "Errors were found in one or more branches. Exiting with error."
        exit 1  # Завершаем скрипт с кодом ошибки
    else
        log $operation "INFO" "No errors found. Exiting successfully."
        exit 0  # Завершаем скрипт без ошибок
    fi
}

# Функция для вывода массива в формате JSON
to_json() {
    local branches=()
    
    # Собираем уникальные ветки
    for key in "${!branch_status[@]}"; do
        branch_name="${key%%,*}" # Отделяем название ветки от статуса или сообщения
        if [[ ! " ${branches[@]} " =~ " ${branch_name} " ]]; then
            branches+=("$branch_name")
        fi
    done

    local first=true
    echo -n "{"
    for branch in "${branches[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo -n ", "
        fi
        
        # Формируем JSON-структуру для каждой ветки
        echo -n "\"$branch\": {"
        echo -n "\"status\": \"${branch_status[$branch,status]}\", "
        echo -n "\"message\": \"${branch_status[$branch,message]}\""
        echo -n "}"
    done
    echo "}"
}



add_host_to_known_hosts "$GITLAB_ADDR"
add_host_to_known_hosts "$GITHUB_ADDR"

check_and_add_remote "$GITLAB" "$GITLAB_SSH"
check_and_add_remote "$GITHUB" "$GITHUB_SSH"

log "MAIN" "INFO" "Все необходимые репозитории добавлены или уже присутствуют."

fetch_all_remotes

create_local_origin "$GITLAB"
create_local_origin "$GITHUB"

merge_into_local "$GITHUB"

log "RESULTS" "INFO" "Итоги обработки веток:"
# Выводим результат в формате JSON
to_json
check_for_errors

