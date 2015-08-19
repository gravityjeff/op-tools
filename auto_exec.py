#!/usr/bin/env python
#-*- coding = utf-8 -*-

## 需要两个配置文件：config.txt和iplist.txt
## config.txt 格式为：
##ThreadNum:1
##port:22
##local_dir:testdir
##remote_dir:testdir
##alter_auth:chmod 755 testdir
##exec_program:./test.sh
#################################
## iplist.txt格式为：
## 192.168.1.1 root 123123
## 支持多个ip，每行都要按上面格式


import Queue
import sys
import threading
import paramiko
import socket
from threading import Thread
import time
 
class WorkThread(Thread):
    def __init__(self, workQueue, timeout=1):
        Thread.__init__(self)
        self.timeout = timeout
        self.setDaemon(False)
        self.workQueue = workQueue
        self.start()
 
    def run(self):
        emptyQueue = 0
        while True:
            try:
                callable, username, password, ipAddress, port,comms = self.workQueue.get(timeout = self.timeout)
                callable(username,password, ipAddress, port,comms)
                 
            except Queue.Empty:
                print threading.currentThread().getName(),":queue is empty ; sleep 5 seconds\n"
                emptyQueue += 1
                time.sleep(5)
                if emptyQueue == 5:
                    print threading.currentThread().getName(),'i  quit,the queue is empty'
                    break
            except Exception, error:
                print error
 
class ThreadPool:
    def __init__(self, num_of_threads=10):
        self.workQueue = Queue.Queue()
        self.threads = []
        self.__createThreadPool(num_of_threads)
     
    def __createThreadPool(self, num_of_threads):
        for i in range(num_of_threads):
            thread = WorkThread(self.workQueue)
            self.threads.append(thread)
     
    def wait_for_complete(self):
        while len(self.threads):
            thread = self.threads.pop()
            if thread.isAlive():
                thread.join()
 
    def add_job(self, callable, username, password, ipAddress, Port,comms):
        self.workQueue.put((callable, username, password, ipAddress, Port,comms))
         
def doSth(usernam,password,hostname,port,comm):
    print usernam,password,hostname,port,comm
    try:
                 
        t = paramiko.Transport((hostname,int(port)))
        t.connect(username=username,password=password)
        sftp=paramiko.SFTPClient.from_transport(t)
        sftp.put(comm['local_dir'],comm['remote_dir'])
    except Exception,e:
        print 'upload files failed:',e
        t.close()
    finally:
        t.close()
     
     
    try:
        ssh = paramiko.SSHClient()
        ssh.load_system_host_keys()
        ssh.set_missing_host_key_policy(paramiko.MissingHostKeyPolicy())
        ssh.connect(hostname, port=int(port), username=username, password=password)
        ssh.exec_command(comm['alter_auth'])
        ssh.exec_command(comm['exec_program'])
    except Exception,e:
        print 'chang file auth or execute the file failed:',e
    ssh.close()
         
     
def readConf():
    comm={}
    try:
        f = file('config.txt','r')
        for l in f:
            sp = l.split(':')
            comm[sp[0]]=sp[1].strip('\n')
    except Exception,e:
        print 'open file config.txt failed:',e
    f.close()
     
    return comm
 
if __name__ == "__main__":
   
    configList = readConf()
     
    wm = ThreadPool(int(configList['ThreadNum']))
         
    try:
        ipFile = file('iplist.txt','r')
    except:
        print "[-] iplist.txt Open file Failed!"
        sys.exit(1)
         
    for line in ipFile:
        IpAdd,username,pwd = line.strip('\r\n').split(' ')
        wm.add_job(doSth,username,pwd,IpAdd,configList['port'],configList)
