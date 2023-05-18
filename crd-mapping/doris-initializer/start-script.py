import os, sys, time, MySQLdb

host = os.environ.get('FE_SVC')
port = os.environ.get('FE_QUERY_PORT')
acc_user = os.environ.get('ACC_USER')
acc_password = os.environ.get('ACC_PASSWORD')

# connect to fe
retry_count = 0
for i in range(0, 10):
    try:
        conn = MySQLdb.connect(host=host, port=port, user=acc_user, passwd=acc_password, connect_timeout=5)
    except MySQLdb.OperationalError as e:
        print(e)
        retry_count += 1
        time.sleep(1)
        continue
    break
if retry_count == 10:
    sys.exit(1)

# modify the password of default user
password_dir = '/etc/doris/password'

for file in os.listdir(password_dir):
    if file.startswith('.'):
        continue
    user = file
    with open(os.path.join(password_dir, file), 'r') as f:
        lines = f.read().splitlines()
        password = lines[0] if len(lines) > 0 else ""
    if user == 'root' or user == 'admin':
        conn.cursor().execute("set password for %s = password(%s);", (user, password))

# execute init sql scripts
with open('/etc/doris/init.sql', 'r') as f:
    sql = f.read()
    conn.cursor().execute(sql)
    conn.commit()

conn.cursor().execute("flush privileges;")
conn.commit()
conn.close()
