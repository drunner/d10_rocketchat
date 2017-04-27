-- drunner service configuration for ROCKETCHAT

-- requires use of dRunner's proxy, which means it's only useful for
-- situations where you expose the service to the internet 
-- (proxy currently supports LetsEncrypt or auto generated self-signed certs -
--  not certs you control)

-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}"
dbcontainer="drunner-${SERVICENAME}-mongodb"
dbvolume="drunner-${SERVICENAME}-database"
certvolume="drunner-${SERVICENAME}-certvolume"
network="drunnerproxy"

cmongo="mongo:3.2"
crocket="rocket.chat:0.55.1"

-- addconfig( VARIABLENAME, DEFAULTVALUE, DESCRIPTION )
addconfig("MODE","fake","LetsEncrypt mode: fake, staging, production")
addconfig("EMAIL","","LetsEncrypt email")
addconfig("DOMAIN","","Domain for the rocket.chat service")
addconfig("TIMEZONE","Pacific/Auckland","Timezone for Rocket.chat")

-- overrideable.
sMode="${MODE}"
sEmail="${EMAIL}"
sDomain="${DOMAIN}"

function start_mongo()
    -- fire up the mongodb server.
    result,output=docker("run",
    "--name",dbcontainer,
    "--network=" .. network,
    "-v", dbvolume .. ":/data/db",
    "-d",cmongo,
    "--smallfiles",
    "--oplogSize","128",
    "--replSet","rs0")
    dieunless( result, "Failed to start mongodb : "..output)
    dieunless( dockerwait(dbcontainer, "27017"), "Mongodb didn't respond on port 27017 in the expected timeframe.")

    -- run the mongo replica config
    result=docker("run","--rm",
    "--network=" .. network ,
    cmongo,
    "mongo",dbcontainer .. "/rocketchat","--eval",
    "rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'localhost:27017' } ]})"
    )
    dieunless(result, "Mongodb replica init failed")
end

function start_rocketchat()
    -- and rocketchat on port 3000
    result,output=docker("run",
    "--name",rccontainer,
    "--network=" .. network ,
    "--env","MONGO_URL=mongodb://" .. dbcontainer .. ":27017/rocketchat",
    "--env","MONGO_OPLOG_URL=mongodb://" .. dbcontainer .. ":27017/local",
    "--env","TZ=${TIMEZONE}",
    "-d",crocket)

    dieunless(result, "Failed to start rocketchat on port ${PORT} : "..output)
    dieunless(dockerwait(rccontainer, "3000", 120), "Rocketchat didn't respond in the expected timeframe.")
end

function start()
   dieif( isdockerrunning(dbcontainer), "rocketchat is already running.")

   start_mongo()
   start_rocketchat()
      
   -- use dRunner's built-in proxy to expose rocket.chat over SSL (port 443) on host.
   -- disable timeouts because rocket.chat keeps websockets open for ages.
   dieunless( proxyenable(sDomain,rccontainer,3000,sEmail,sMode,false), "Couldn't enable proxy")
end

function stop()
   msgunless(proxydisable(),"Couldn't disable proxy") 

   dockerstop(rccontainer)
   dockerstop(dbcontainer)
end

function uninstall()
   stop()
   -- we retain the database volume
end

function obliterate()
   stop()
   msgunless( dockerdeletevolume(dbvolume), "Unable to remove docker volume "..dbvolume)
end

-- install
function install()
   dockerpull(cmongo)
   dockerpull(crocket)
   dieunless( dockercreatevolume(dbvolume), "Couldn't create docker volume "..dbvolume)
end

function backup()
   docker("pause",rccontainer)
   docker("pause",dbcontainer)

   dieunless( dockerbackup(dbvolume), "Failed to backup "..dbvolume )

   docker("unpause",dbcontainer)
   docker("unpause",rccontainer)
end

function restore()
   dockerpull(cmongo)
   dockerpull(crocket)
   dieunless( dockerrestore(dbvolume), "Couldn't restore "..dbvolume)
   
-- set mode to fake for safety!
   setconfig("MODE","fake")
end

function selftest()
   sDomain="travis"
   sEmail="j@842.be"
   sMode="fake"
   print("Starting...")
   start()
   print("Stopping...")
   stop()
   print("Self test complete.")
end

function help()
   return [[
   NAME
      ${SERVICENAME} - Run a rocket.chat server.
      Configure the HTTPS settings (Domain, LetsEncrypt email) before
      starting.

   SYNOPSIS
      ${SERVICENAME} help             - This help
      ${SERVICENAME} configure        - Configure domain, email, mode.
      ${SERVICENAME} start            - Start the service
      ${SERVICENAME} stop             - Stop it

   DESCRIPTION
      Built from ${IMAGENAME}.
   ]]
end
