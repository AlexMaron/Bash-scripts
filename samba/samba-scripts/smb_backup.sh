#!/bin/bash
#
# Inctemental backup script.
# Store incremental data frome backup server and delele backups older than N days.

user='fenix'
date=`date "+%Y-%m-%dT%H"`
increment_backup="back-${date}"
HOST="${user}@192.168.0.215"
SOURCE='/srv/samba/'
BACKUPFOLDER="/home/${user}/backups/"
DEST="/home/${user}/backups/$increment_backup"

# Создает на сервере бекапа папку логов если она не существует.
ssh $HOST "
          if [[ ! -d ${BACKUPFOLDER}log ]]; then
              mkdir -p ${BACKUPFOLDER}log
          fi
          if [[ ! -d ${BACKUPFOLDER}new-files/$increment_backup/ ]]; then
              mkdir -p ${BACKUPFOLDER}new-files/$increment_backup
          fi
"
#  Основной блок - создает инкрементный бекап на удаленном сервере.
#+ Инкрементальный бекап создается с помощью встроенной функции
#+ rsync которая позволяет сравнивать директорию на локальном хосте
#+ с целевой директорией на удаленном хосте и в случае совпадения
#+ вместе копирования совпавшего файла создает hard link на уже
#+ существующий inode.
if [[ `ssh ${HOST} "ls ${BACKUPFOLDER}full_back &>/dev/null"` -ne 0 ]]; then # Если полной копии нет, создает ее.
    rsync -azA \
	  --exclude /srv/samba/scanner/
          ${SOURCE} ${HOST}:${BACKUPFOLDER}full_back 2>> /var/log/rsync.err
else # В другом случае, делает инкрементное копирование.
    rsync -azA \
          --exclude /srv/samba/scanner/ \
          --link-dest=/home/fenix/backups/current/ \
          ${SOURCE} ${HOST}:${DEST} 2>> /var/log/rsync.err \
          && ssh ${HOST} \
          "rm -f ${BACKUPFOLDER}current \
          && ln -s $DEST /home/fenix/backups/current
	  "

#  Дополнительный уровень бекапа, который копирирует из
#+ последнего инкременального бекапа новые или переименованные
#+ файлы (у которых в stat хард линки имеют значение меньше
#+ числа 2).
ssh $HOST <<'EOF'
          back_date=`date "+%Y-%m-%dT%H"`
          incremental_backup="back-$back_date"
          BACK_DEST=/home/fenix/backups/$incremental_backup
          cd $BACK_DEST 
          find -type f -printf '%n %p\n' | awk '$1 < 2{$1="";print}' | xargs -I{} cp --parents {} ../new-files/$incremental_backup/
EOF


#  Удаление старых инкрементный бекапов и
#+ и логирование этого события.
ssh ${HOST} " 
          find ${BACKUPFOLDER}back* \
          -maxdepth 1 \
          -ctime +7 \
          -type d \
          -exec rm -rv {} + &> ${BACKUPFOLDER}log/fulldel.backup
          sed -i '$ a =============  ${date}  =============' \
          ${BACKUPFOLDER}/log/fulldel.backup

          cat ${BACKUPFOLDER}log/fulldel.backup | \
          awk -F'[T]' '{print $1}' | \
	  grep -v '^rm:' | \
          grep directory \
          > ${BACKUPFOLDER}log/lessdel.backup

          cat ${BACKUPFOLDER}log/fulldel.backup | \
          sed '/^removed/d' | \
          sed '/^=====/d' \
          >> ${BACKUPFOLDER}log/errors.backup
" 
fi

exit
