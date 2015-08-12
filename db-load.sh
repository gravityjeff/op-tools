#!/bin/bash

## 大部分变量如帐号密码ip等记在op_profile里
. /home/script/op_profile
. ~/.bash_profile 

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2

function help() {
                echo "Usage: `basename $0`-P partNum -L loadaverage -I IoUtil -T binlogTime -C [User|Character]"
                exit 1
}

specialPj='xxx'
if [ $PROJ_NAME == $specialPj ];then
    partNum=`ls -l /data/| fgrep $MYSQLMASTER |grep ^d|awk '{print $NF}'|awk -F'_' '{print $2}'`
else
    partNum=`ls -l /data/| fgrep $MYSQLMASTER |grep ^d|awk '{print $NF}'|sed 's/[^0-9]//g'`
fi

if [ -z "$partNum" ];then
    echo "this db is Not partXX,exit"
    exit
fi

loadLimit=5	## load average阀值为5
ioLimit=80	## iostat util 阀值为80
timeLimit=1800	## binlog生成时间1800秒
uOrC=$DbLoad_UserOrCharacter

dbName=part$partNum
mysqlCmd="mysql -h$MYSQLIP -u$MYSQLUSER -p$MYSQLPASSWD $MYSQLDB "

TEN_MILLION=10000000
while getopts ":P:L:I:T:C:" Option;do
        case $Option in
                P ) partNum=${OPTARG};;
                L ) loadLimit=${OPTARG} ;;
                I ) ioLimit=${OPTARG}   ;;
                T ) timeLimit=${OPTARG} ;;
                C ) uOrC=${OPTARG} ;;
                * ) help           ;;
        esac
done
shift $(($OPTIND - 1))

monitorDir=`/home/script/monitor_getdir.sh`
today=`/bin/date +'%Y%m%d'`   ## 20121113
today1=`/bin/date +'%m-%d'`   ## 08-07 
hostname=`hostname`
todayDir=${monitorDir}___${today}

if [ ! -e $todayDir ];then
    echo "no dir $todayDir,exit"
    exit
fi

cd $todayDir

curLoad=`tail -5 ${hostname}___cpu.txt |fgrep 'load average'|awk -F':' '{print $NF}'|cut -d, -f1|sed 's/ //g'`

ioutil=`tail -5 ${hostname}___iostat.txt |grep sda|awk '{print $NF}'`

## 获取binglog日志生成速度作为写操作频繁度的粗放指标
binlogList=`ls -l /log/|fgrep $today1|fgrep 'mysql-bin.'|fgrep -v mysql-bin.index|awk '{print $NF}'`
declare -a array

for i in $binlogList;do
    mTime=`stat /log/$i |grep Modify|awk '{print $2,$3}'|cut -d. -f1`
    t=`date -d  "$mTime" +%s`
    array=(${array[@]} "$t")
done

len=${#array[@]}

## 删除最新的没写完的binlog
unset array[$((len-1))]
minTime=9999999
len=${#array[@]}
if [ $len -ge 2 ];then
    n=0
    while [ $n -le $((len-2)) ];do
        t1=${array[$n]}
        t2=${array[$((n+1))]}
        let tmpTime=$t2-$t1
        if [ $minTime -ge $tmpTime ];then
            minTime=$tmpTime
        fi

        let n++
    done
else
    minTime='NOT enough binlog'
fi

DATE=`/bin/date +"%Y-%m-%d %H:%M:%S"`
function printTime(){
        echo "time:[$DATE]"
}

logFile=$todayDir/${hostname}___dbload.txt

printTime >> $logFile
echo "cpu load | io util | binlog time" >> $logFile
echo "$curLoad|$ioutil|$minTime" >> $logFile
echo "################################################################################################" >> $logFile

### 判断结果是否超过阀值,小数取整计算
isOk='true'
curLoad=`echo $curLoad | awk -F. '{print $1}' `
ioutil=`echo $ioutil |awk -F. '{print $1}'`

if [[ $curLoad =~ ^[0-9]+$ ]] && [[ $curLoad -gt $loadLimit ]];then
    echo -n "Warn:load is $curLoad;"
    isOk='false'
fi

if [[ $ioutil =~ ^[0-9]+$ ]] && [[ $ioutil -gt $ioLimit ]];then
    echo -n "Warn:IO is $ioutil;"
    isOk='false'
fi

if [[ $minTime =~ ^[0-9]+$ ]] && [[ $minTime -lt $timeLimit ]];then
    echo -n "Warn:binlogTime is $minTime;"
    isOk='false'
fi

## 这个函数是把超过阀值的db记录+1，超过一定次数后报警
function addWarn(){
    $mysqlCmd -e "update $DbLoad_tableName set WarnCount=WarnCount+1 where Name='$dbName'"
    curWarn=`$mysqlCmd -e "select WarnCount from $DbLoad_tableName where DbName='$dbName'" | fgrep -v WarnCount`
    if [[ $curWarn -ge 20 ]];then
        curTime=`date +"%Y%m%d%H%M%S"`
        $mysqlCmd -e "update $DbLoad_tableName set Weight=0,WarnCount=0 where DbName='$dbName'"
        $mysqlCmd -e "update $reloadTable set UpdateTime=$curTime where Name='$DbLoad_reloadItem'"
        echo "$curTime: $dbName set 0 weight" >> /tmp/db-load-check.log
    fi
}

curHour=`date +'%k'`

## 业务繁忙时间从上午8点到晚上21点会产生报警
if [ $curHour -ge 8 ] && [ $curHour -le 21 ] && [ $isOk == 'false' ];then
    echo ""
    addWarn
else
    echo "OK"
fi
