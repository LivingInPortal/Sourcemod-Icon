#include <sourcemod>
#include <sdktools>

#pragma semicolon 1

#define CONFIGPATH "configs/icon.cfg"

public Plugin:myinfo =
{
	name = "Icon",
	author = "benefitOfLaughing",
	description = "Put an icon above the head",
	version = "0.1",
	url = "www.sourcemod.net"
};

enum AuthOption
{
	AuthOption_Flags,
	AuthOption_Steam,
};

new bool:g_bPrecached = false;
new g_Models[MAXPLAYERS + 1] = {-1, ...};
new Handle:g_hKv = INVALID_HANDLE;
new Handle:g_hClasses = INVALID_HANDLE;
new Handle:g_hClassIndexes = INVALID_HANDLE;
new Handle:g_hAuthStack = INVALID_HANDLE;

public OnPluginStart()
{
	Initialize();

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
}

public OnPluginEnd()
{
	for(new i = 0; i < sizeof(g_Models); i++) {
		Entity_SafeDelete(g_Models[i]);
	}
}

public OnMapStart()
{
	g_bPrecached = false;
	
	Kv_Parse();
	LoadFileFromConfig(g_hKv);
	LoadPlayerFromConfig(g_hKv);
	
	g_bPrecached = true;
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontbroadcast)
{
	if(!g_bPrecached)	return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(IsClientInGame(client) && IsPlayerAlive(client)) {
		GiveModel(client);
	}
	
	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontbroadcast)
{
	if(!g_bPrecached)	return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	Entity_SafeDelete(g_Models[client]);
	g_Models[client] = -1;
	
	return Plugin_Continue;
}

bool:GiveModel(client)
{
	new AuthOption:auth;
	new String:sAttribute[30];
	new String:sClass[50];
	for(new i = 0; i < GetArraySize(g_hAuthStack); i++) {
		new Handle:datapack = Handle:GetArrayCell(g_hAuthStack, i);
		ResetPack(datapack);

		auth = ReadPackCell(datapack);
		ReadPackString(datapack, sAttribute, sizeof(sAttribute));
		ReadPackString(datapack, sClass, sizeof(sClass));
		
		switch(auth) {
			case AuthOption_Flags:
			{
				if(CheckClientFlags(client, sAttribute)) {
					if(!ClassGiveModel(client, sClass)) {
						LogMessage("Couldnt give class %s for client %d", sClass, client);
					}
					return true;
				}
			}
			case AuthOption_Steam:
			{
				if(CheckClientSteam(client, sAttribute)) {
					if(!ClassGiveModel(client, sClass)) {
						LogMessage("Couldnt give class %s for client %d", sClass, client);
					}
					return true;
				}
			}
		}
	}
	return false;
}

Kv_Parse()
{
	new String:filepath[PLATFORM_MAX_PATH];
	new Handle:kv = CreateKeyValues("Icon");

	BuildPath(Path_SM, filepath, sizeof(filepath), CONFIGPATH);

	if(!FileToKeyValues(kv, filepath))
		SetFailState("I cannot load keyvalue file from %s", CONFIGPATH);

	if(g_hKv != INVALID_HANDLE)
		CloseHandle(g_hKv);
	g_hKv = kv;
}

Initialize()
{
	g_hClasses = CreateArray(4096);
	g_hClassIndexes = CreateTrie();
	g_hAuthStack = CreateArray();
}

CreateIcon(String:vmt[])
{
	new sprite = CreateEntityByName("env_sprite_oriented");
	
	if(sprite == -1)	return -1;

	DispatchKeyValue(sprite, "classname", "env_sprite_oriented");
	DispatchKeyValue(sprite, "spawnflags", "1");
	DispatchKeyValue(sprite, "scale", "0.3");
	DispatchKeyValue(sprite, "rendermode", "1");
	DispatchKeyValue(sprite, "rendercolor", "255 255 255");
	DispatchKeyValue(sprite, "model", vmt);
	if(DispatchSpawn(sprite))	return sprite;

	return -1;
}

PlaceAndBindIcon(client, entity)
{
	new Float:origin[3];

	if(IsValidEntity(entity)) {
		GetClientAbsOrigin(client, origin);
		origin[2] = origin[2] + 90.0;
		TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", client);
	}
}

Entity_SafeDelete(entity)
{
	if(IsValidEntity(entity)) {
		AcceptEntityInput(entity, "Kill");
	}
}

bool:CheckClientFlags(client, String:flags[])
{
	if(flags[0] == '\0')
		return true;
	new bitstring = ReadFlagString(flags);
	return ((GetAdminFlags(GetUserAdmin(client), Access_Effective)) & bitstring) == bitstring;
}

bool:CheckClientSteam(client, String:steamid[])
{
	new String:client_steamid[32];
	if(!GetClientAuthId(client, AuthId_Steam2, client_steamid, sizeof(client_steamid)))	return false;
	return StrEqual(client_steamid, steamid);
}

LoadPlayerFromConfig(Handle:kv)
{
	new String:sSection[50];
	new String:sAuth[10];
	new String:sAttribute[30];
	new String:sClass[50];
	new AuthOption:auth;

	ClearArray(g_hAuthStack);

	KvRewind(kv);

	if(!KvJumpToKey(kv, "Player"))	return false;
	if(!KvGotoFirstSubKey(kv))	return false;

	do {
		KvGetSectionName(kv, sSection, sizeof(sSection));
		KvGetString(kv, "auth", sAuth, sizeof(sAuth));
		KvGetString(kv, "class", sClass, sizeof(sClass));

		if(sClass[0] == '\0') {
			LogMessage("Undefined class name in \"Player %s\"", sClass);
			continue;
		}

		if(StrEqual("flags", sAuth, false)) {
			auth = AuthOption_Flags;
			KvGetString(kv, "flags", sAttribute, sizeof(sAttribute));
		} else if(StrEqual("steam", sAuth, false)) {
			auth = AuthOption_Steam;
			KvGetString(kv, "steam", sAttribute, sizeof(sAttribute));
		} else {
			LogMessage("Unrecognized option in \"Player %s\"", sClass);
			continue;
		}

		new Handle:datapack = CreateDataPack();
		// 1: Auth
		WritePackCell(datapack, auth);
		// 2: Auth Attribute
		WritePackString(datapack, sAttribute);
		// 3: Class Name
		WritePackString(datapack, sClass);

		PushArrayCell(g_hAuthStack, datapack);
	} while(KvGotoNextKey(kv));

	return 0;
}

// Load config to turn file information into classes
LoadFileFromConfig(Handle:kv)
{
	new Handle:hPrecachedFiles = CreateArray();
	new String:sClass[50];
	new String:sVMT[128];
	new String:sVTF[128];
	new count;
	
	ClearArray(g_hClasses);
	ClearTrie(g_hClassIndexes);

	KvRewind(kv);

	// No file, no meaning. Return false to show error
	if(!KvJumpToKey(kv, "File"))	return false;
	if(!KvGotoFirstSubKey(kv))	return false;

	do {
		KvGetString(kv, "class", sClass, sizeof(sClass));
		KvGetString(kv, "vmt", sVMT, sizeof(sVMT));
		KvGetString(kv, "vtf", sVTF, sizeof(sVTF));

		if(FindStringInArray(hPrecachedFiles, sVMT) == -1 && FindStringInArray(hPrecachedFiles, sVTF) == -1) {
			if(!PrecacheModel(sVMT)) {
				LogMessage("Failed to precache file in class: %s", sClass);
				continue;
			}
		} else {
			continue;
		}

		AddFileToDownloadsTable(sVMT);
		AddFileToDownloadsTable(sVTF);

		PushArrayString(hPrecachedFiles, sVMT);
		PushArrayString(hPrecachedFiles, sVTF);

		count = GetArraySize(g_hClasses);
		// Save VMT filepath
		PushArrayString(g_hClasses, sVMT);
		SetTrieValue(g_hClassIndexes, sClass, count);
	} while(KvGotoNextKey(kv));

	CloseHandle(hPrecachedFiles);

	return 0;
}

bool:ClassGiveModel(client, String:class[])
{
	new index;
	new String:filepath[128];

	if(!GetTrieValue(g_hClassIndexes, class, index))	return false;
	GetArrayString(g_hClasses, index, filepath, sizeof(filepath));

	Entity_SafeDelete(g_Models[client]);
	g_Models[client] = CreateIcon(filepath);

	if(g_Models[client] != -1) {
		PlaceAndBindIcon(client, g_Models[client]);
		return true;
	}
	
	return false;
}
