import MySQLdb
import os
import sys
import time

host = os.environ.get('FE_SVC')
port = os.environ.get('FE_QUERY_PORT')
acc_user = os.environ.get('ACC_USER')
acc_password = os.environ.get('ACC_PASSWORD')

database = os.environ.get('DATABASE')
repo_name = os.environ.get('REPO_NAME')
create_repo_sql = os.environ.get('CREATE_REPO_SQL')
backup_sql = os.environ.get('BACKUP_SQL')

watch_interval = 3


def create_conn():
    retry_count = 0
    _conn = None
    for i in range(0, 10):
        try:
            _conn = MySQLdb.connect(host=host, port=port, user=acc_user, passwd=acc_password, connect_timeout=5)
        except MySQLdb.OperationalError as e:
            print(e)
            retry_count += 1
            time.sleep(1)
            continue
        break
    if retry_count == 10:
        print('Failed to connect to FE.')
        sys.exit(1)
    return _conn


def exist_backup_task(_conn):
    cursor = _conn.cursor().execute("show backup from %s;" % database)
    results = cursor.fetchall()
    if len(results) == 0:
        return False
    else:
        state = results[0][3]
        if state == 'FINISHED' or state == 'CANCELLED':
            return False
        else:
            return True


def exist_restore_task(_conn):
    cursor = _conn.cursor().execute("show restore from %s;" % database)
    results = cursor.fetchall()
    if len(results) == 0:
        return False
    state = results[0][4]
    if state == 'FINISHED' or state == 'CANCELLED':
        return False
    else:
        return True


def create_repo(_conn):
    try:
        cursor = _conn.cursor().execute(create_repo_sql)
        cursor.execute("show create repository for %s;" % repo_name)
    except MySQLdb.Error as error:
        if "repository not exist" in str(error):
            print("Repository(%s) does not exist, creating it..." % repo_name)
            _conn.cursor().execute(create_repo_sql)
            print("Repository(%s) created successfully." % repo_name)
        else:
            print("Failed to create repository(%s): %s" % (repo_name, error))
            sys.exit(1)


def watch_backup_task(_conn):
    while True:
        cursor = _conn.cursor().execute("show backup from %s;" % database)
        results = cursor.fetchall()
        if len(results) == 0:
            continue
        state = results[0][3]
        if state == 'FINISHED':
            print("Backup task finished successfully.")
            break
        elif state == 'CANCELLED':
            print("Backup task failed.")
            error_stack = results[0][11]
            status = results[0][12]
            print("status: \n%s" % status)
            print("error stack: \n%s" % error_stack)
            break
        time.sleep(watch_interval)


conn = create_conn()

print("Checking if there is a running backup or restore task under the database($s)" % database)
if exist_backup_task(conn):
    print('There is already a running backup task under database(%s)!' % database)
    sys.exit(1)
if exist_restore_task(conn):
    print('There is already a running restore task under database(%s)!' % database)
    sys.exit(1)

print("Creating repository(%s) if necessary." % repo_name)
create_repo(conn)

print("Executing backup sql.")
conn.cursor.execute(backup_sql)

print("Watching backup task state...")
watch_backup_task(conn)
