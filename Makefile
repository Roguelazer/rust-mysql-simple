mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfile_dir := $(dir $(mkfile_path))
MYSQL_DATA_DIR = $(mkfile_dir)tests/rust-mysql-simple-test
MYSQL_SSL_CA = $(mkfile_dir)tests/ca-cert.pem
MYSQL_SSL_CERT = $(mkfile_dir)tests/server-cert.pem
MYSQL_SSL_KEY = $(mkfile_dir)tests/server-key.pem
MYSQL_PORT = 3307
BASEDIR := $(shell mysqld --verbose --help 2>/dev/null | grep -e '^basedir' | awk '{ print $$2 }')
OS := $(shell uname)

FEATURES := "" "socket" "ssl" "uuid" "ssl socket uuid"
BENCH_FEATURES := "nightly" "nightly socket" "nightly ssl" "nightly socket ssl"

define run-mysql
if [ -e $(MYSQL_DATA_DIR)/mysqld.pid ];\
then \
	kill -9 `cat $(MYSQL_DATA_DIR)/mysqld.pid`; \
	rm -rf $(MYSQL_DATA_DIR) || true; \
fi

if [ -e $(MYSQL_DATA_DIR) ];\
then \
	rm -rf $(MYSQL_DATA_DIR) || true; \
fi

mkdir -p $(MYSQL_DATA_DIR)

if (mysql --version | grep 5.7 >>/dev/null);\
then \
	mysql_install_db --no-defaults \
                     --basedir=$(BASEDIR) \
                     --datadir=$(MYSQL_DATA_DIR)/data; \
else \
    mysql_install_db --no-defaults \
                     --basedir=$(BASEDIR) \
                     --datadir=$(MYSQL_DATA_DIR)/data \
                     --force; \
fi

mysqld --no-defaults \
       --basedir=$(BASEDIR) \
       --bind-address=127.0.0.1 \
       --datadir=$(MYSQL_DATA_DIR)/data \
       --max-allowed-packet=32M \
       --pid-file=$(MYSQL_DATA_DIR)/mysqld.pid \
       --port=$(MYSQL_PORT) \
       --innodb_file_per_table=1 \
       --innodb_file_format=Barracuda \
       --innodb_log_file_size=256M \
       --ssl \
       --ssl-ca=$(MYSQL_SSL_CA) \
       --ssl-cert=$(MYSQL_SSL_CERT) \
       --ssl-key=$(MYSQL_SSL_KEY) \
       --ssl-cipher=DHE-RSA-AES256-SHA \
       --socket=$(MYSQL_DATA_DIR)/mysqld.sock &

sleep 10

if [ -e ~/.mysql_secret ]; \
then \
    mysqladmin -h127.0.0.1 \
	           --port=$(MYSQL_PORT) \
			   -u root \
			   -p"`cat ~/.mysql_secret | grep -v Password`" password 'password'; \
else \
    mysqladmin -h127.0.0.1 --port=$(MYSQL_PORT) -u root password 'password'; \
fi
endef

all: lib doc

target/deps: lib

target/tests/mysql: test

lib:
	cargo build --release

doc:
	cargo doc

test:
	$(run-mysql)
	if ! (cargo test --no-default-features); \
	then \
		echo TESTING WITHOUT FEATURES; \
		kill -9 `cat $(MYSQL_DATA_DIR)/mysqld.pid`; \
		rm -rf $(MYSQL_DATA_DIR) || true; \
		exit 1; \
	fi
	for var in $(FEATURES); \
	do \
		echo TESTING FEATURS: $$var; \
		if ! (cargo test --no-default-features --features "$$var"); \
		then \
			kill -9 `cat $(MYSQL_DATA_DIR)/mysqld.pid`; \
			rm -rf $(MYSQL_DATA_DIR) || true; \
			exit 1; \
		fi \
	done

	@kill -9 `cat $(MYSQL_DATA_DIR)/mysqld.pid`
	@rm -rf $(MYSQL_DATA_DIR) || true

bench:
	$(run-mysql)
	for var in $(BENCH_FEATURES); \
	do \
		echo TESTING FEATURS: $$var; \
		if ! (cargo bench --no-default-features --features "$$var"); \
		then \
			kill -9 `cat $(MYSQL_DATA_DIR)/mysqld.pid`; \
			rm -rf $(MYSQL_DATA_DIR) || true; \
			exit 1; \
		fi \
	done

	@kill -9 `cat $(MYSQL_DATA_DIR)/mysqld.pid`
	@rm -rf $(MYSQL_DATA_DIR) || true

clean:
	cargo clean
