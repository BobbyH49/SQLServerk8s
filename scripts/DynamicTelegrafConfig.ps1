$podName = kubectl get pods -n sqlmonitor -o jsonpath="{.items[?(@.metadata.labels.app=='influxdb')].metadata.name}"
$influxClusterIP = kubectl get services -n sqlmonitor influxdb -o jsonpath="{.spec.clusterIP}"
$sqlmonBucket = kubectl exec -n sqlmonitor -c influxdb $podName -- influx bucket list -n sqlmon --hide-headers
$sqlmonBucketId = $sqlmonBucket.substring(0, 16)
$influxApiTokenData = kubectl exec -n sqlmonitor -c influxdb $podName -- influx auth create -o sqlmon --write-bucket $sqlmonBucketId --hide-headers
$influxApiToken = $InfluxAPITokenData.substring(18, 88)
$mssql19_0_lb_ClusterIP = kubectl get services -n sql19 mssql19-0-lb -o jsonpath="{.spec.clusterIP}"
$mssql19_1_lb_ClusterIP = kubectl get services -n sql19 mssql19-1-lb -o jsonpath="{.spec.clusterIP}"
$mssql19_2_lb_ClusterIP = kubectl get services -n sql19 mssql19-2-lb -o jsonpath="{.spec.clusterIP}"
$mssql22_0_lb_ClusterIP = kubectl get services -n sql22 mssql22-0-lb -o jsonpath="{.spec.clusterIP}"
$mssql22_1_lb_ClusterIP = kubectl get services -n sql22 mssql22-1-lb -o jsonpath="{.spec.clusterIP}"
$mssql22_2_lb_ClusterIP = kubectl get services -n sql22 mssql22-2-lb -o jsonpath="{.spec.clusterIP}"

$connectionsConf = ""
if ($null -ne $mssql19_0_lb_ClusterIP) {
  $connectionsConf += "    `"Server=$($mssql19_0_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql19_1_lb_ClusterIP) {
  $connectionsConf += "    `"Server=$($mssql19_1_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql19_2_lb_ClusterIP) {
  $connectionsConf += "    `"Server=$($mssql19_2_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql22_0_lb_ClusterIP) {
  $connectionsConf += "    `"Server=$($mssql22_0_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql22_1_lb_ClusterIP) {
  $connectionsConf += "    `"Server=$($mssql22_1_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql22_2_lb_ClusterIP) {
  $connectionsConf += "    `"Server=$($mssql22_2_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`","
}

Write-Host "$(Get-Date) - Generate config.yaml for telegraf"
$telegrafConfScript = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: telegraf-config
data:
  telegraf.conf: |+
    # Configuration for telegraf agent
    [agent]
      ## Default data collection interval for all inputs
      interval = "10s"
      ## Rounds collection interval to 'interval'
      ## ie, if interval="10s" then always collect on :00, :10, :20, etc.
      round_interval = true

      ## Telegraf will send metrics to outputs in batches of at most
      ## metric_batch_size metrics.
      ## This controls the size of writes that Telegraf sends to output plugins.
      metric_batch_size = 1000

      ## Maximum number of unwritten metrics per output.  Increasing this value
      ## allows for longer periods of output downtime without dropping metrics at the
      ## cost of higher maximum memory usage.
      metric_buffer_limit = 10000

      ## Collection jitter is used to jitter the collection by a random amount.
      ## Each plugin will sleep for a random time within jitter before collecting.
      ## This can be used to avoid many plugins querying things like sysfs at the
      ## same time, which can have a measurable effect on the system.
      collection_jitter = "0s"

      ## Default flushing interval for all outputs. Maximum flush_interval will be
      ## flush_interval + flush_jitter
      flush_interval = "10s"
      ## Jitter the flush interval by a random amount. This is primarily to avoid
      ## large write spikes for users running a large number of telegraf instances.
      ## ie, a jitter of 5s and interval 10s means flushes will happen every 10-15s
      flush_jitter = "0s"

      ## By default or when set to "0s", precision will be set to the same
      ## timestamp order as the collection interval, with the maximum being 1s.
      ##   ie, when interval = "10s", precision will be "1s"
      ##       when interval = "250ms", precision will be "1ms"
      ## Precision will NOT be used for service inputs. It is up to each individual
      ## service input to set the timestamp at the appropriate precision.
      ## Valid time units are "ns", "us" (or "µs"), "ms", "s".
      precision = ""

      ## Log at debug level.
      # debug = false
      ## Log only error level messages.
      # quiet = false

      ## Log target controls the destination for logs and can be one of "file",
      ## "stderr" or, on Windows, "eventlog".  When set to "file", the output file
      ## is determined by the "logfile" setting.
      # logtarget = "file"

      ## Name of the file to be logged to when using the "file" logtarget.  If set to
      ## the empty string then logs are written to stderr.
      # logfile = ""

      ## The logfile will be rotated after the time interval specified.  When set
      ## to 0 no time based rotation is performed.  Logs are rotated only when
      ## written to, if there is no log activity rotation may be delayed.
      # logfile_rotation_interval = "0d"

      ## The logfile will be rotated when it becomes larger than the specified
      ## size.  When set to 0 no size based rotation is performed.
      # logfile_rotation_max_size = "0MB"

      ## Maximum number of rotated archives to keep, any older logs are deleted.
      ## If set to -1, no archives are removed.
      # logfile_rotation_max_archives = 5

      ## Pick a timezone to use when logging or type 'local' for local time.
      ## Example: America/Chicago
      # log_with_timezone = ""

      ## Override default hostname, if empty use os.Hostname()
      hostname = ""
      ## If set to true, do no set the "host" tag in the telegraf agent.
      omit_hostname = false
    [[outputs.influxdb_v2]]
      ## The URLs of the InfluxDB cluster nodes.
      ##
      ## Multiple URLs can be specified for a single cluster, only ONE of the
      ## urls will be written to each interval.
      ##   ex: urls = ["https://us-west-2-1.aws.cloud2.influxdata.com"]
      urls = ["http://$($influxClusterIP):8086"]

      ## Token for authentication.
      token = "$($influxApiToken)"

      ## Organization is the name of the organization you wish to write to; must exist.
      organization = "sqlmon"

      ## Destination bucket to write into.
      bucket = "sqlmon"

      ## The value of this tag will be used to determine the bucket.  If this
      ## tag is not set the 'bucket' option is used as the default.
      # bucket_tag = ""

      ## If true, the bucket tag will not be added to the metric.
      # exclude_bucket_tag = false

      ## Timeout for HTTP messages.
      # timeout = "5s"

      ## Additional HTTP headers
      # http_headers = {"X-Special-Header" = "Special-Value"}

      ## HTTP Proxy override, if unset values the standard proxy environment
      ## variables are consulted to determine which proxy, if any, should be used.
      # http_proxy = "http://corporate.proxy:3128"

      ## HTTP User-Agent
      # user_agent = "telegraf"

      ## Content-Encoding for write request body, can be set to "gzip" to
      ## compress body or "identity" to apply no encoding.
      # content_encoding = "gzip"

      ## Enable or disable uint support for writing uints influxdb 2.0.
      # influx_uint_support = false

      ## Optional TLS Config for use on HTTP connections.
      # tls_ca = "/etc/telegraf/ca.pem"
      # tls_cert = "/etc/telegraf/cert.pem"
      # tls_key = "/etc/telegraf/key.pem"
      ## Use TLS but skip chain & host verification
      # insecure_skip_verify = false
    # Read metrics from Microsoft SQL Server
    [[inputs.sqlserver]]
      ## Specify instances to monitor with a list of connection strings.
      ## All connection parameters are optional.
      ## By default, the host is localhost, listening on default port, TCP 1433.
      ##   for Windows, the user is the currently running AD user (SSO).
      ##   See https://github.com/denisenkom/go-mssqldb for detailed connection
      ##   parameters, in particular, tls connections can be created like so:
      ##   "encrypt=true;certificate=<cert>;hostNameInCertificate=<SqlServer host fqdn>"
      servers = [
$connectionsYaml
      ]

      ## Authentication method
      ## valid methods: "connection_string", "AAD"
      # auth_method = "connection_string"

      ## "database_type" enables a specific set of queries depending on the database type. If specified, it replaces azuredb = true/false and query_version = 2
      ## In the config file, the sql server plugin section should be repeated each with a set of servers for a specific database_type.
      ## Possible values for database_type are - "SQLServer" or "AzureSQLDB" or "AzureSQLManagedInstance" or "AzureSQLPool"

      database_type = "SQLServer"

      ## A list of queries to include. If not specified, all the below listed queries are used.
      include_query = []

      ## A list of queries to explicitly ignore.
      exclude_query = ["SQLServerAvailabilityReplicaStates", "SQLServerDatabaseReplicaStates"]

      ## Queries enabled by default for database_type = "SQLServer" are -
      ## SQLServerPerformanceCounters, SQLServerWaitStatsCategorized, SQLServerDatabaseIO, SQLServerProperties, SQLServerMemoryClerks,
      ## SQLServerSchedulers, SQLServerRequests, SQLServerVolumeSpace, SQLServerCpu, SQLServerAvailabilityReplicaStates, SQLServerDatabaseReplicaStates,
      ## SQLServerRecentBackups

      ## Queries enabled by default for database_type = "AzureSQLDB" are -
      ## AzureSQLDBResourceStats, AzureSQLDBResourceGovernance, AzureSQLDBWaitStats, AzureSQLDBDatabaseIO, AzureSQLDBServerProperties,
      ## AzureSQLDBOsWaitstats, AzureSQLDBMemoryClerks, AzureSQLDBPerformanceCounters, AzureSQLDBRequests, AzureSQLDBSchedulers

      ## Queries enabled by default for database_type = "AzureSQLManagedInstance" are -
      ## AzureSQLMIResourceStats, AzureSQLMIResourceGovernance, AzureSQLMIDatabaseIO, AzureSQLMIServerProperties, AzureSQLMIOsWaitstats,
      ## AzureSQLMIMemoryClerks, AzureSQLMIPerformanceCounters, AzureSQLMIRequests, AzureSQLMISchedulers

      ## Queries enabled by default for database_type = "AzureSQLPool" are -
      ## AzureSQLPoolResourceStats, AzureSQLPoolResourceGovernance, AzureSQLPoolDatabaseIO, AzureSQLPoolWaitStats,
      ## AzureSQLPoolMemoryClerks, AzureSQLPoolPerformanceCounters, AzureSQLPoolSchedulers

      ## Following are old config settings
      ## You may use them only if you are using the earlier flavor of queries, however it is recommended to use
      ## the new mechanism of identifying the database_type there by use it's corresponding queries

      ## Optional parameter, setting this to 2 will use a new version
      ## of the collection queries that break compatibility with the original
      ## dashboards.
      ## Version 2 - is compatible from SQL Server 2012 and later versions and also for SQL Azure DB
      # query_version = 2

      ## If you are using AzureDB, setting this to true will gather resource utilization metrics
      # azuredb = false

      ## Toggling this to true will emit an additional metric called "sqlserver_telegraf_health".
      ## This metric tracks the count of attempted queries and successful queries for each SQL instance specified in "servers".
      ## The purpose of this metric is to assist with identifying and diagnosing any connectivity or query issues.
      ## This setting/metric is optional and is disabled by default.
      # health_metric = false

      ## Possible queries accross different versions of the collectors
      ## Queries enabled by default for specific Database Type

      ## database_type =  AzureSQLDB  by default collects the following queries
      ## - AzureSQLDBWaitStats
      ## - AzureSQLDBResourceStats
      ## - AzureSQLDBResourceGovernance
      ## - AzureSQLDBDatabaseIO
      ## - AzureSQLDBServerProperties
      ## - AzureSQLDBOsWaitstats
      ## - AzureSQLDBMemoryClerks
      ## - AzureSQLDBPerformanceCounters
      ## - AzureSQLDBRequests
      ## - AzureSQLDBSchedulers

      ## database_type =  AzureSQLManagedInstance by default collects the following queries
      ## - AzureSQLMIResourceStats
      ## - AzureSQLMIResourceGovernance
      ## - AzureSQLMIDatabaseIO
      ## - AzureSQLMIServerProperties
      ## - AzureSQLMIOsWaitstats
      ## - AzureSQLMIMemoryClerks
      ## - AzureSQLMIPerformanceCounters
      ## - AzureSQLMIRequests
      ## - AzureSQLMISchedulers

      ## database_type =  AzureSQLPool by default collects the following queries
      ## - AzureSQLPoolResourceStats
      ## - AzureSQLPoolResourceGovernance
      ## - AzureSQLPoolDatabaseIO
      ## - AzureSQLPoolOsWaitStats,
      ## - AzureSQLPoolMemoryClerks
      ## - AzureSQLPoolPerformanceCounters
      ## - AzureSQLPoolSchedulers

      ## database_type =  SQLServer by default collects the following queries
      ## - SQLServerPerformanceCounters
      ## - SQLServerWaitStatsCategorized
      ## - SQLServerDatabaseIO
      ## - SQLServerProperties
      ## - SQLServerMemoryClerks
      ## - SQLServerSchedulers
      ## - SQLServerRequests
      ## - SQLServerVolumeSpace
      ## - SQLServerCpu
      ## - SQLServerRecentBackups
      ## and following as optional (if mentioned in the include_query list)
      ## - SQLServerAvailabilityReplicaStates
      ## - SQLServerDatabaseReplicaStates

      ## Version 2 by default collects the following queries
      ## Version 2 is being deprecated, please consider using database_type.
      ## - PerformanceCounters
      ## - WaitStatsCategorized
      ## - DatabaseIO
      ## - ServerProperties
      ## - MemoryClerk
      ## - Schedulers
      ## - SqlRequests
      ## - VolumeSpace
      ## - Cpu

      ## Version 1 by default collects the following queries
      ## Version 1 is deprecated, please consider using database_type.
      ## - PerformanceCounters
      ## - WaitStatsCategorized
      ## - CPUHistory
      ## - DatabaseIO
      ## - DatabaseSize
      ## - DatabaseStats
      ## - DatabaseProperties
      ## - MemoryClerk
      ## - VolumeSpace
      ## - PerformanceMetrics
"@

$telegrafConfFile = "$Env:DeploymentDir\yaml\Monitor\Telegraf\config.yaml"
$telegrafConfScript | Out-File -FilePath $telegrafConfFile -force

$connectionsYaml = ""
if ($null -ne $mssql19_0_lb_ClusterIP) {
  $connectionsYaml += "        `"Server=$($mssql19_0_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql19_1_lb_ClusterIP) {
  $connectionsYaml += "        `"Server=$($mssql19_1_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql19_2_lb_ClusterIP) {
  $connectionsYaml += "        `"Server=$($mssql19_2_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql22_0_lb_ClusterIP) {
  $connectionsYaml += "        `"Server=$($mssql22_0_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql22_1_lb_ClusterIP) {
  $connectionsYaml += "        `"Server=$($mssql22_1_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`",`r`n"
}
if ($null -ne $mssql22_2_lb_ClusterIP) {
  $connectionsYaml += "        `"Server=$($mssql22_2_lb_ClusterIP);Port=1433;User Id=Telegraf;Password=$($Env:adminPassword);app name=telegraf;log=1;`","
}

Write-Host "$(Get-Date) - Generate telegraf.conf for InfluxDB"
$telegrafInfluxScript = @"
[[outputs.influxdb_v2]]
  ## The URLs of the InfluxDB cluster nodes.
  ##
  ## Multiple URLs can be specified for a single cluster, only ONE of the
  ## urls will be written to each interval.
  ##   ex: urls = ["https://us-west-2-1.aws.cloud2.influxdata.com"]
  urls = ["http://$($influxClusterIP):8086"]

  ## Token for authentication.
  token = "$($influxApiToken)"

  ## Organization is the name of the organization you wish to write to; must exist.
  organization = "sqlmon"

  ## Destination bucket to write into.
  bucket = "sqlmon"

  ## The value of this tag will be used to determine the bucket.  If this
  ## tag is not set the 'bucket' option is used as the default.
  # bucket_tag = ""

  ## If true, the bucket tag will not be added to the metric.
  # exclude_bucket_tag = false

  ## Timeout for HTTP messages.
  # timeout = "5s"

  ## Additional HTTP headers
  # http_headers = {"X-Special-Header" = "Special-Value"}

  ## HTTP Proxy override, if unset values the standard proxy environment
  ## variables are consulted to determine which proxy, if any, should be used.
  # http_proxy = "http://corporate.proxy:3128"

  ## HTTP User-Agent
  # user_agent = "telegraf"

  ## Content-Encoding for write request body, can be set to "gzip" to
  ## compress body or "identity" to apply no encoding.
  # content_encoding = "gzip"

  ## Enable or disable uint support for writing uints influxdb 2.0.
  # influx_uint_support = false

  ## Optional TLS Config for use on HTTP connections.
  # tls_ca = "/etc/telegraf/ca.pem"
  # tls_cert = "/etc/telegraf/cert.pem"
  # tls_key = "/etc/telegraf/key.pem"
  ## Use TLS but skip chain & host verification
  # insecure_skip_verify = false
# Read metrics from Microsoft SQL Server
[[inputs.sqlserver]]
  ## Specify instances to monitor with a list of connection strings.
  ## All connection parameters are optional.
  ## By default, the host is localhost, listening on default port, TCP 1433.
  ##   for Windows, the user is the currently running AD user (SSO).
  ##   See https://github.com/denisenkom/go-mssqldb for detailed connection
  ##   parameters, in particular, tls connections can be created like so:
  ##   "encrypt=true;certificate=<cert>;hostNameInCertificate=<SqlServer host fqdn>"
  servers = [
$connectionsConf
  ]

  ## Authentication method
  ## valid methods: "connection_string", "AAD"
  # auth_method = "connection_string"

  ## "database_type" enables a specific set of queries depending on the database type. If specified, it replaces azuredb = true/false and query_version = 2
  ## In the config file, the sql server plugin section should be repeated each with a set of servers for a specific database_type.
  ## Possible values for database_type are - "SQLServer" or "AzureSQLDB" or "AzureSQLManagedInstance" or "AzureSQLPool"

  database_type = "SQLServer"

  ## A list of queries to include. If not specified, all the below listed queries are used.
  include_query = []

  ## A list of queries to explicitly ignore.
  exclude_query = ["SQLServerAvailabilityReplicaStates", "SQLServerDatabaseReplicaStates"]

  ## Queries enabled by default for database_type = "SQLServer" are -
  ## SQLServerPerformanceCounters, SQLServerWaitStatsCategorized, SQLServerDatabaseIO, SQLServerProperties, SQLServerMemoryClerks,
  ## SQLServerSchedulers, SQLServerRequests, SQLServerVolumeSpace, SQLServerCpu, SQLServerAvailabilityReplicaStates, SQLServerDatabaseReplicaStates,
  ## SQLServerRecentBackups

  ## Queries enabled by default for database_type = "AzureSQLDB" are -
  ## AzureSQLDBResourceStats, AzureSQLDBResourceGovernance, AzureSQLDBWaitStats, AzureSQLDBDatabaseIO, AzureSQLDBServerProperties,
  ## AzureSQLDBOsWaitstats, AzureSQLDBMemoryClerks, AzureSQLDBPerformanceCounters, AzureSQLDBRequests, AzureSQLDBSchedulers

  ## Queries enabled by default for database_type = "AzureSQLManagedInstance" are -
  ## AzureSQLMIResourceStats, AzureSQLMIResourceGovernance, AzureSQLMIDatabaseIO, AzureSQLMIServerProperties, AzureSQLMIOsWaitstats,
  ## AzureSQLMIMemoryClerks, AzureSQLMIPerformanceCounters, AzureSQLMIRequests, AzureSQLMISchedulers

  ## Queries enabled by default for database_type = "AzureSQLPool" are -
  ## AzureSQLPoolResourceStats, AzureSQLPoolResourceGovernance, AzureSQLPoolDatabaseIO, AzureSQLPoolWaitStats,
  ## AzureSQLPoolMemoryClerks, AzureSQLPoolPerformanceCounters, AzureSQLPoolSchedulers

  ## Following are old config settings
  ## You may use them only if you are using the earlier flavor of queries, however it is recommended to use
  ## the new mechanism of identifying the database_type there by use it's corresponding queries

  ## Optional parameter, setting this to 2 will use a new version
  ## of the collection queries that break compatibility with the original
  ## dashboards.
  ## Version 2 - is compatible from SQL Server 2012 and later versions and also for SQL Azure DB
  # query_version = 2

  ## If you are using AzureDB, setting this to true will gather resource utilization metrics
  # azuredb = false

  ## Toggling this to true will emit an additional metric called "sqlserver_telegraf_health".
  ## This metric tracks the count of attempted queries and successful queries for each SQL instance specified in "servers".
  ## The purpose of this metric is to assist with identifying and diagnosing any connectivity or query issues.
  ## This setting/metric is optional and is disabled by default.
  # health_metric = false

  ## Possible queries accross different versions of the collectors
  ## Queries enabled by default for specific Database Type

  ## database_type =  AzureSQLDB  by default collects the following queries
  ## - AzureSQLDBWaitStats
  ## - AzureSQLDBResourceStats
  ## - AzureSQLDBResourceGovernance
  ## - AzureSQLDBDatabaseIO
  ## - AzureSQLDBServerProperties
  ## - AzureSQLDBOsWaitstats
  ## - AzureSQLDBMemoryClerks
  ## - AzureSQLDBPerformanceCounters
  ## - AzureSQLDBRequests
  ## - AzureSQLDBSchedulers

  ## database_type =  AzureSQLManagedInstance by default collects the following queries
  ## - AzureSQLMIResourceStats
  ## - AzureSQLMIResourceGovernance
  ## - AzureSQLMIDatabaseIO
  ## - AzureSQLMIServerProperties
  ## - AzureSQLMIOsWaitstats
  ## - AzureSQLMIMemoryClerks
  ## - AzureSQLMIPerformanceCounters
  ## - AzureSQLMIRequests
  ## - AzureSQLMISchedulers

  ## database_type =  AzureSQLPool by default collects the following queries
  ## - AzureSQLPoolResourceStats
  ## - AzureSQLPoolResourceGovernance
  ## - AzureSQLPoolDatabaseIO
  ## - AzureSQLPoolOsWaitStats,
  ## - AzureSQLPoolMemoryClerks
  ## - AzureSQLPoolPerformanceCounters
  ## - AzureSQLPoolSchedulers

  ## database_type =  SQLServer by default collects the following queries
  ## - SQLServerPerformanceCounters
  ## - SQLServerWaitStatsCategorized
  ## - SQLServerDatabaseIO
  ## - SQLServerProperties
  ## - SQLServerMemoryClerks
  ## - SQLServerSchedulers
  ## - SQLServerRequests
  ## - SQLServerVolumeSpace
  ## - SQLServerCpu
  ## - SQLServerRecentBackups
  ## and following as optional (if mentioned in the include_query list)
  ## - SQLServerAvailabilityReplicaStates
  ## - SQLServerDatabaseReplicaStates

  ## Version 2 by default collects the following queries
  ## Version 2 is being deprecated, please consider using database_type.
  ## - PerformanceCounters
  ## - WaitStatsCategorized
  ## - DatabaseIO
  ## - ServerProperties
  ## - MemoryClerk
  ## - Schedulers
  ## - SqlRequests
  ## - VolumeSpace
  ## - Cpu

  ## Version 1 by default collects the following queries
  ## Version 1 is deprecated, please consider using database_type.
  ## - PerformanceCounters
  ## - WaitStatsCategorized
  ## - CPUHistory
  ## - DatabaseIO
  ## - DatabaseSize
  ## - DatabaseStats
  ## - DatabaseProperties
  ## - MemoryClerk
  ## - VolumeSpace
  ## - PerformanceMetrics
"@

$telegrafInfluxFile = "$Env:DeploymentDir\yaml\Monitor\InfluxDB\telegraf.conf"
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[System.IO.File]::WriteAllLines($telegrafInfluxFile, $telegrafInfluxScript, $Utf8NoBomEncoding)
