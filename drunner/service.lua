-- drunner service configuration for ROCKETCHAT
-- based on https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml
-- and https://github.com/docker-library/docs/tree/master/rocket.chat

rccontainer="drunner-${SERVICENAME}-rocketchat"
dbcontainer="drunner-${SERVICENAME}-mongodb"


function drunner_setup()
-- addconfig(NAME, DESCRIPTION, DEFAULT VALUE, TYPE, REQUIRED)
   addconfig("PORT","The port to run rocketchat on.","3000","port",true)

   addconfig("ROOTURL","The root URL for rocketchat.","http://localhost","string",true)

-- not user settable
   addconfig("RUNNING","Is the service running","false","bool",true,false)

-- addvolume(NAME, [BACKUP], [EXTERNAL])
   addvolume("drunner-${SERVICENAME}-uploads",true,false)

end


-- everything past here are functions that can be run from the commandline,
-- e.g. helloworld run

function start()
--   generate()
   dconfig_set("RUNNING","true")

   if (drunning("drunner-${SERVICENAME}-rocketchat")) then
      print("rocketchat is already running.")
   else
      -- fire up the mongodb server.
      result=drun("docker","run",
      "--name",dbcontainer,
      "-d","mongo:3.0",
      "--smallfiles")

      if result~=0 then
        print(dsub("Failed to start mongodb."))
      end

      -- and rocketchat
      result=drun("docker","run",
      "--name",rccontainer,
      "-p","${PORT}:3000",
      "--env","ROOT_URL=${ROOTURL}",
      "--link",dbcontainer .. ":db",
      "-d","rocket.chat")

      if result~=0 then
        print(dsub("Failed to start rocketchat on port ${PORT}."))
      end
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
