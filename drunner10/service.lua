-- drunner service configuration for ROCKETCHAT
-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}-rocketchat"
dbcontainer="drunner-${SERVICENAME}-mongodb"
caddycontainer="drunner-${SERVICENAME}-caddy"
dbvolume="drunner-${SERVICENAME}-database"
certvolume="drunner-${SERVICENAME}-certvolume"
network="drunner-${SERVICENAME}-network"

-- addconfig( VARIABLENAME, DEFAULTVALUE, DESCRIPTION )
addconfig("PORT","443","The port to run rocketchat on.")
addconfig("MODE","fake","LetsEncrypt mode: fake, staging, production")
addconfig("EMAIL","","LetsEncrypt email")
addconfig("HOSTNAME","","Hostname for the rocket.chat service")


function start_mongo()
    -- fire up the mongodb server.
    result=docker("run",
    "--name",dbcontainer,
    "--network=" .. network ,
    "-v", dbvolume .. ":/data/db",
    "-d","mongo:3.2",
    "--smallfiles",
    "--oplogSize","128",
    "--replSet","rs0")

    if result~=0 then
      print("Failed to start mongodb.")
    end

-- Wait for port 27017 to come up in dbcontainer (30s timeout on the given network)
    if not dockerwait(dbcontainer, "27017") then
      print("Mongodb didn't seem to start?")
    end

    -- run the mongo replica config
    result=docker("run","--rm",
    "--network=" .. network ,
    "mongo:3.2",
    "mongo",dbcontainer .. "/rocketchat","--eval",
    "rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'localhost:27017' } ]})"
    )

    if result~=0 then
      print("Mongodb replica init failed")
    end

end

function start_rocketchat()
    -- and rocketchat on port 3000
    result=docker("run",
    "--name",rccontainer,
    "--network=" .. network ,
    "--env","MONGO_URL=mongodb://" .. dbcontainer .. ":27017/rocketchat",
    "--env","MONGO_OPLOG_URL=mongodb://" .. dbcontainer .. ":27017/local",
    "-d","rocket.chat")

    if result~=0 then
      print("Failed to start rocketchat on port ${PORT}.")
    end
end

function start_caddy()
  result=docker("run",
    "--name",caddycontainer,
    "--network=" .. network ,
    "-p","${PORT}:443",
    "-v", certvolume .. ":/root/.caddy",
    "-e","MODE=${MODE}",
    "-e","EMAIL=${EMAIL}",
    "-e","CERT_HOST=${HOSTNAME}",
    "-e","SERVICE_HOST="..rccontainer,
    "-e","SERVICE_PORT=3000",
    "-d",
    "j842/caddy"
  )

    if result~=0 then
      print("Failed to start caddy on port ${PORT}.")
    end

-- docker run --rm -p 443:443 -e EMAIL="j@842.be" -e CERT_HOST="dev" -e SERVICE_HOST=dev -e SERVICE_PORT=80 -e MODE="fake" j842/caddy

-- bridge to outside world.
--   docker("network","connect","bridge",caddycontainer)

end

function start()
   if (dockerrunning(dbcontainer)) then
      print("rocketchat is already running.")
   else
      start_mongo()
      start_rocketchat()
      start_caddy()
   end
end

function stop()
  dockerstop(caddycontainer)
  dockerstop(rccontainer)
  dockerstop(dbcontainer)
end

function uninstall()
   stop()
   docker("network","rm",network)
   -- we retain the database volume
end

function obliterate()
   stop()
   docker("network","rm",network)
   dockerdeletevolume(dbvolume)
   dockerdeletevolume(certvolume)
end

-- install
function install()
  dockerpull("mongo:3.2")
  dockerpull("rocket.chat")
  dockerpull("j842/caddy")
  dockercreatevolume(dbvolume)
  dockercreatevolume(certvolume)
  docker("network","create",network)
--  start() ?
end

function backup()
   docker("pause",rccontainer)
   docker("pause",dbcontainer)

   dockerbackup(dbvolume)
   dockerbackup(certvolume)

   docker("unpause",dbcontainer)
   docker("unpause",rccontainer)
end

function restore()
   dockerrestore(dbvolume)
   dockerrestore(certvolume)

-- set mode to fake for safety!
   dconfig_set("MODE","fake")
end

function help()
   return [[
   NAME
      ${SERVICENAME} - Run a rocket.chat server on port ${PORT}.

   SYNOPSIS
      ${SERVICENAME} help             - This help
      ${SERVICENAME} configure port   - Set port
      ${SERVICENAME} start            - Make it go!
      ${SERVICENAME} stop             - Stop it

   DESCRIPTION
      Built from ${IMAGENAME}.
   ]]
end
