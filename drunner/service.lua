-- drunner service configuration for ROCKETCHAT
-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}-rocketchat"
dbcontainer="drunner-${SERVICENAME}-mongodb"

ulvolume="drunner-${SERVICENAME}-uploads"
dbvolume="drunner-${SERVICENAME}-database"

-- dbcontainer="db"


function drunner_setup()
-- addconfig(NAME, DESCRIPTION, DEFAULT VALUE, TYPE, REQUIRED)
   addconfig("PORT","The port to run rocketchat on.","80","port",true)

-- not user settable
   addconfig("RUNNING","Is the service running","false","bool",true,false)

-- addvolume(NAME, [BACKUP], [EXTERNAL])
   addvolume(ulvolume,true,false)
   addvolume(dbvolume,true,false)

end


-- everything past here are functions that can be run from the commandline,
-- e.g. helloworld run

function start_mongo()
    -- fire up the mongodb server.
    result=drun("docker","run",
    "--name",dbcontainer,
    "-v", dbvolume .. ":/data/db",
    "-d","mongo:3.0",
    "--smallfiles",
    "--oplogSize","128",
    "--replSet","rs0")

    if result~=0 then
      print(dsub("Failed to start mongodb."))
    end

    -- wait until it's available
    result=drun("docker","run","--rm",
    "--link", dbcontainer.. ":db",
    "drunner/rocketchat",
    "/usr/local/bin/waitforit.sh","-h","db","-p","27017","-t","60"
    )

    if result~=0 then
      print(dsub("Mongodb didn't seem to start?"))
    end

    -- run the mongo replica config
    result=drun("docker","exec",dbcontainer,
    "mongo","127.0.0.1/rocketchat","--eval",
    "rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'localhost:27017' } ]})"
    )     
    
    if result~=0 then
      print(dsub("Mongodb replica init failed"))
    end
end

function start_rocketchat()
    -- and rocketchat
    result=drun("docker","run",
    "--name",rccontainer,
    "-p","${PORT}:3000",
    "-v", ulvolume .. ":/app/uploads",
    "--link", dbcontainer .. ":db",
    "-d","rocket.chat")

    if result~=0 then
      print(dsub("Failed to start rocketchat on port ${PORT}."))
    end

    -- fix the uploads directory so the rocketchat user can access it.
    result=drun("docker","exec","--user","root",rccontainer,"/bin/bash","chown","-R","rocketchat","/app/uploads")
end



function start()
--   generate()
   dconfig_set("RUNNING","true")

   if (drunning(dbcontainer)) then
      print("rocketchat is already running.")
   else
      start_mongo()
      start_rocketchat()
   end

--   autogenerate()
end

function stop()
  dconfig_set("RUNNING","false")
  dstop(dbcontainer)
  dstop(rccontainer)
end

function obliterate_start()
   stop()
end

function uninstall_start()
   stop()
end

function update_start()
  dstop(dbcontainer)
  dstop(rccontainer)
end

function update_end()
   if (dconfig_get("RUNNING")=="true") then
      start()
   end
end

function backup_start()
   drun("docker","pause",rccontainer)
   drun("docker","pause",dbcontainer)
end

function backup_end()
   drun("docker","unpause",dbcontainer)
   drun("docker","unpause",rccontainer)
end


function help()
   return [[
   NAME
      ${SERVICENAME} - Run a rocket.chat server on the given port.

   SYNOPSIS
      ${SERVICENAME} help             - This help
      ${SERVICENAME} configure        - Set port and URL
      ${SERVICENAME} start            - Make it go!
      ${SERVICENAME} stop             - Stop it

   DESCRIPTION
      Built from ${IMAGENAME}.
   ]]
end
