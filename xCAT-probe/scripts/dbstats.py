# -*- encoding: utf-8 -*-
# !/usr/bin/python
from __future__ import print_function
import argparse
import json
import os
import sys
import time

BUF_SIZE = 8192


class Reader(object):
    def __init__(self, file):
        self.f_size = os.stat(file).st_size
        self.f_pos = self.f_size
        self.file = file
        self.buf_list = []
        self.remain = None
        self.f = None

    def open(self):
        if self.f is None:
            self.f = open(self.file)

    def close(self):
        if self.f is not None:
            self.f.close()
            self.f = None

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def _read(self):
        if self.f_pos == 0:
            return None

        size = BUF_SIZE
        if self.f_pos - BUF_SIZE >= 0:
            self.f.seek(self.f_pos - BUF_SIZE)
        else:
            self.f.seek(0)
            size = self.f_pos - 0
        buf = self.f.read(size)
        if self.remain is not None:
            self.buf_list = (buf + self.remain).split('\n')
        else:
            self.buf_list = buf.split('\n')
        if size == BUF_SIZE:
            self.remain = self.buf_list[0]
            self.buf_list = self.buf_list[1:]
        else:
            self.remain = None
        self.f_pos -= size

        return self.buf_list

    def get_next(self):
        ret = self._get_next()
        if ret is not None:
            return ret

        while self._read() is not None:
            ret = self._get_next()
            if ret is not None:
                return ret

        return None


class CommandReader(Reader):
    def __init__(self, file):
        super(CommandReader, self).__init__(file)
        self.cmd = {}

    def _get_next(self):
        """ Extract data from the commands log file of xcat
        Format::

            [Date]       2017-09-04 17:52:10
            [ClientType] cli
            [Request]    xdsh c910f04x35v07 'echo "nameserver 9.0.2.1" >> /etc/resolv.conf'
            [Response]
            [ElapsedTime] 0 s
        :return: command dict if found, None if not found
        """
        for i, b in enumerate(self.buf_list[::-1]):
            if b.find('[ElapsedTime]') == 0:
                self.cmd['elapsed'] = float(b.split(' ')[1])
            elif b.find('[Request]') == 0:
                self.cmd['request'] = " ".join(
                    b.rstrip().split(' ')[1:]).strip().replace(',', ' ')
            elif b.find('[Date]') == 0:
                temp = b.split(' ')
                self.cmd['date'] = '%s %s' % (temp[-2], temp[-1])

                if all(k in self.cmd for k in ('date', 'request', 'elapsed')):
                    cmd = self.cmd
                    self.cmd = {}
                    self.buf_list = self.buf_list[0:len(self.buf_list) - i - 1]
                    return cmd
        return None


class DBTraceReader(Reader):
    def __init__(self, file):
        super(DBTraceReader, self).__init__(file)
        self.year = str(time.localtime().tm_year)

    def _get_next(self):
        """Extract information from syslog file of xcat
        Format::

            Sep  4 22:16:38 c910f04x12v02 xcat[6692]: [DB Trace]: {"msg":{"table":"nodegroup","method":"xCAT::Table::getAllEntries"},"type":"end_sql","elapsed":"0.00042s"}

        :return: A dict contains the time stamp and db dict if db trace log is
                 found. None if nothing about db trace log found.
        """
        for i, b in enumerate(self.buf_list[::-1]):
            pos = b.find('[DB Trace]:')
            if pos == -1:
                continue
            date = b[0:15]
            conv = time.strptime('%s %s' % (self.year, date),
                                 "%Y %b %d %H:%M:%S")
            # TODO: the year value is not included in the current syslog
            try:
                ret = {'stamp': int(time.mktime(conv)),
                       'db': json.loads(b[pos + 12:])}
            except ValueError:
                if b.find('message repeated') != -1:
                    # syslog will add [ ] around the json message.
                    ret = {'stamp': int(time.mktime(conv)),
                           'db': json.loads(b[pos + 12:-1])}
                else:
                    raise

            self.buf_list = self.buf_list[0:len(self.buf_list) - i - 1]
            return ret

        return None


class TimeStamp(object):
    def __init__(self, kwargs):
        if 'date' in kwargs:
            a = time.strptime(kwargs['date'], "%Y-%m-%d %H:%M:%S")
            self.start = int(time.mktime(a))
        else:
            raise
        if 'elapsed' in kwargs:
            self.end = self.start + int(kwargs['elapsed']) + 1
        else:
            raise


class Analysis(object):
    def __init__(self, command_log_file, cluster_log_file):
        self.command_log_file = command_log_file
        self.cluster_log_file = cluster_log_file

    def _stat(self, record, data):
        elapsed = 0
        if 'elapsed' in data:
            # elapsed = float('%.3f' % float(data['elapsed'][:-1]))
            elapsed = float(data['elapsed'][:-1])
        if data['type'] == 'end_sql':
            if data['msg']['method'].startswith('xCAT::Table::get'):
                record['get_sql_time'] += elapsed
            elif data['msg']['method'].startswith('xCAT::Table::set'):
                record['set_sql_time'] += elapsed
            elif data['msg']['method'].startswith('xCAT::Table::del'):
                record['del_sql_time'] += elapsed
        elif data['type'] == 'end':
            if data['msg']['method'].startswith('xCAT::Table::get'):
                record['get_sub_time'] += elapsed
            elif data['msg']['method'].startswith('xCAT::Table::set'):
                record['set_sub_time'] += elapsed
            elif data['msg']['method'].startswith('xCAT::Table::del'):
                record['del_sub_time'] += elapsed
        elif data['type'] == 'start_sql':
            if data['msg']['method'].startswith('xCAT::Table::get'):
                if data['msg']['table'] not in record['get_tables']:
                    record['get_tables'][data['msg']['table']] = 1
                else:
                    record['get_tables'][data['msg']['table']] += 1
            elif data['msg']['method'].startswith('xCAT::Table::set'):
                if data['msg']['table'] not in record['set_tables']:
                    record['set_tables'][data['msg']['table']] = 1
                else:
                    record['set_tables'][data['msg']['table']] += 1
            elif data['msg']['method'].startswith('xCAT::Table::del'):
                if data['msg']['table'] not in record['del_tables']:
                    record['del_tables'][data['msg']['table']] = 1
                else:
                    record['del_tables'][data['msg']['table']] += 1
        elif data['type'] == 'build_cache':
            if data['msg']['table'] not in record['build_cache']:
                record['build_cache'][data['msg']['table']] = 1
            else:
                record['build_cache'][data['msg']['table']] += 1
        elif data['type'] == 'cache_hit':
            if data['msg']['table'] not in record['cache_hit']:
                record['cache_hit'][data['msg']['table']] = 1
            else:
                record['cache_hit'][data['msg']['table']] += 1

    def process(self, latest, specific_cmd):
        if specific_cmd is not None:
            latest = None

        self._print_header()
        with CommandReader(self.command_log_file) as cmd_reader:
            cmd = cmd_reader.get_next()
            trace = None
            index = 0
            db_reader = DBTraceReader(self.cluster_log_file)
            db_reader.open()
            while cmd is not None:
                if specific_cmd is not None and not cmd['request'].startswith(
                        specific_cmd):
                    cmd = cmd_reader.get_next()
                    continue

                stamp = TimeStamp(cmd)
                if trace is None:
                    trace = db_reader.get_next()

                while trace and trace['stamp'] > stamp.end:
                    trace = db_reader.get_next()
                key = '%s(%s)' % (cmd['request'], cmd['date'])

                record = {'command': key,
                          'elapsed': cmd['elapsed'],
                          'get_sql_time': float(0),
                          'set_sql_time': float(0),
                          'del_sql_time': float(0),
                          'set_sub_time': float(0),
                          'get_sub_time': float(0),
                          'del_sub_time': float(0),
                          'get_tables': {},
                          'set_tables': {},
                          'del_tables': {},
                          'build_cache': {},
                          'cache_hit': {}}

                while trace and trace['stamp'] >= stamp.start:
                    self._stat(record, trace['db'])
                    trace = db_reader.get_next()

                self._print_csv(record)
                index += 1
                if latest is not None and index == latest:
                    break
                cmd = cmd_reader.get_next()
            db_reader.close()

    def _print_header(self):
        print("command,elapsed(precision: 1s),"
              "get_sub_time(s),set_sub_time(s),del_sub_time(s),"
              "get_sql_time(s),set_sql_time(s),del_sql_time(s),"
              "build_cache(times),cache_hit(times),"
              "get_tables(times),set_tables(times),del_tables(times)")

    def _print_csv(self, record):
        print("%(command)s,%(elapsed)f,"
              "%(get_sub_time)f,%(set_sub_time)f,%(del_sub_time)f,"
              "%(get_sql_time)f,%(set_sql_time)f,%(del_sql_time)f,"
              "%(build_cache)s,%(cache_hit)s,"
              "%(get_tables)s,%(set_tables)s,%(del_tables)s\n" %
              {'command': record['command'],
               'elapsed': record['elapsed'],
               'get_sub_time': float('%.3f' % record['get_sub_time']),
               'set_sub_time': float('%.3f' % record['set_sub_time']),
               'del_sub_time': float('%.3f' % record['del_sub_time']),
               'get_sql_time': float('%.3f' % record['get_sql_time']),
               'set_sql_time': float('%.3f' % record['set_sql_time']),
               'del_sql_time': float('%.3f' % record['del_sql_time']),
               'build_cache': self._format_dict(record['build_cache']),
               'cache_hit': self._format_dict(record['cache_hit']),
               'get_tables': self._format_dict(record['get_tables']),
               'set_tables': self._format_dict(record['set_tables']),
               'del_tables': self._format_dict(record['del_tables'])})

    def _format_list(self, a):
        return " ".join(a)

    def _format_dict(self, d):
        ret = []
        for k, v in d.items():
            if type(v) is list:
                ret.append('%s:[%s]', k, " ".join(v))
            elif type(v) is str or type(v) is int:
                ret.append('%s:%s' % (k, str(v)))
        return " ".join(ret)


class StatsShell(object):
    def get_base_parser(self):
        parser = argparse.ArgumentParser(
            prog='dbstats',
            add_help=False,
            formatter_class=HelpFormatter,
        )
        parser.add_argument('-h', '--help',
                            action='store_true',
                            help=argparse.SUPPRESS,
                            )
        parser.add_argument('--clusterlog',
                            help="The syslog file of xcat.",
                            default='/var/log/xcat/cluster.log',
                            type=str)
        parser.add_argument('--commandlog',
                            help="The command log file of xcat.",
                            default='/var/log/xcat/commands.log',
                            type=str)
        parser.add_argument('-n', '--num',
                            help="The recent count of commands to analyze",
                            type=int,
                            default=10)
        parser.add_argument('-c', '--command',
                            help="The specified command to track",
                            type=str,
                            default=None)
        return parser

    def do_help(self, args):
        self.parser.print_help()

    def main(self, argv):
        self.parser = self.get_base_parser()
        (options, args) = self.parser.parse_known_args(argv)

        if options.help:
            self.do_help(options)
            return 0

        a = Analysis(options.commandlog, options.clusterlog)
        a.process(options.num, options.command)


class HelpFormatter(argparse.HelpFormatter):
    def start_section(self, heading):
        # Title-case the headings
        heading = '%s%s' % (heading[0].upper(), heading[1:])
        super(HelpFormatter, self).start_section(heading)


if __name__ == "__main__":
    StatsShell().main(sys.argv[1:])
