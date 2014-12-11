#include <sourcemod>
#include <sdktools>

#pragma semicolon 1

#define DEBUG

#define CONFIGPATH "configs/icon.cfg"

public Plugin:myinfo =
{
	name = "Icon",
	author = "benefitOfLaughing",
	description = "Put an icon above the head",
	version = "0.3",
	url = "www.sourcemod.net"
};

enum AuthOption
{
	AuthOption_Flags,
	AuthOption_Steam,
};

new bool:g_bPrecached = false;
new g_Models[MAXPLAYERS + 1] = {-1, ...};
new Handle:g_hClasses = INVALID_HANDLE;
new Handle:g_hClassIndexes = INVALID_HANDLE;
new Handle:g_hAuthStack = INVALID_HANDLE;

public OnPluginStart()
{
	Initialize();

	HookEvent("player_spawn", Event_PlayerSpawn);
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
	
	new Handle:hKv = Kv_Parse();
	if(hKv == INVALID_HANDLE) {
		SetFailState("I cannot load keyvalue file from %s", CONFIGPATH);
	}

	LoadFileFromConfig(hKv);
	LoadPlayerFromConfig(hKv);

	CloseHandle(hKv);
	
	g_bPrecached = true;
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontbroadcast)
{
	if(!g_bPrecached)	return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(IsClientInGame(client) && IsPlayerAlive(client)) {
		if(GiveModel(client)) {
#if defined DEBUG
			LogMessage("Give Model for client %d", client);
#endif
		}
	}
	
	return Plugin_Continue;
}

public OnGameFrame()
{
	for(new i = 1; i <= MaxClients; i++) {
		if(IsValidEntity(g_Models[i])) {
			CheckClientAliveForModel(i);
		}
	}
}

CheckClientAliveForModel(client)
{
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
#if defined DEBUG
		LogMessage("Delete Model from client %d", client);
#endif
		Entity_SafeDelete(g_Models[client]);
		g_Models[client] = -1;
	}
}

bool:GiveModel(client)
{
	new AuthOption:auth;
	new String:sAttribute[30];
	new String:sClass[50];
	new String:sScale[10];

	for(new i = 0; i < GetArraySize(g_hAuthStack); i++) {
		new Handle:datapack = Handle:GetArrayCell(g_hAuthStack, i);
		ResetPack(datapack);

		auth = ReadPackCell(datapack);
		ReadPackString(datapack, sAttribute, sizeof(sAttribute));
		ReadPackString(datapack, sClass, sizeof(sClass));
		ReadPackString(datapack, sScale, sizeof(sScale));

		switch(auth) {
			case AuthOption_Flags:
			{
				if(!CheckClientFlags(client, sAttribute)) {
					continue;
				}
			}
			case AuthOption_Steam:
			{
				if(!CheckClientSteam(client, sAttribute)) {
					continue;
				}
			}
		}

		if(!ClassGiveModel(client, sClass, sScale)) {
			LogMessage("Couldnt give class %s for client %d", sClass, client);
			return false;
		} else {
			// Success.
			return true;
		}
	}
	// Not found.
	return false;
}

Handle:Kv_Parse()
{
	new String:filepath[PLATFORM_MAX_PATH];
	new Handle:kv = CreateKeyValues("Icon");

	BuildPath(Path_SM, filepath, sizeof(filepath), CONFIGPATH);

	if(!FileToKeyValues(kv, filepath))
		return INVALID_HANDLE;

	return kv;
}

Initialize()
{
	g_hClasses = CreateArray();
	g_hClassIndexes = CreateTrie();
	g_hAuthStack = CreateArray();
}

CreateIcon(const String:vmt[], const String:scale[])
{
#if defined DEBUG
	LogMessage("CreateIcon vmt: %s, scale: %s", vmt, scale);
#endif
	new sprite = CreateEntityByName("env_sprite_oriented");
	
	if(sprite == -1)	return -1;

	DispatchKeyValue(sprite, "classname", "env_sprite_oriented");
	DispatchKeyValue(sprite, "spawnflags", "1");
	DispatchKeyValue(sprite, "scale", scale);
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

bool:CheckClientFlags(client, const String:flags[])
{
	if(flags[0] == '\0')
		return true;
	new bitstring = ReadFlagString(flags);
	return ((GetAdminFlags(GetUserAdmin(client), Access_Effective)) & bitstring) == bitstring;
}

bool:CheckClientSteam(client, const String:steamid[])
{
	new String:client_steamid[32];
	if(!GetClientAuthId(client, AuthId_Steam2, client_steamid, sizeof(client_steamid)))	return false;
	return StrEqual(client_steamid, steamid);
}

LoadPlayerFromConfig(Handle:kv)
{
	new String:sAuth[10];
	new String:sAttribute[30];
	new String:sClass[50];
	new String:sScale[10];
	new AuthOption:auth;

	ClearArray(g_hAuthStack);

	KvRewind(kv);

	if(!KvJumpToKey(kv, "Player"))	return false;
	if(!KvGotoFirstSubKey(kv))	return false;

	do {
		KvGetString(kv, "auth", sAuth, sizeof(sAuth));
		KvGetString(kv, "class", sClass, sizeof(sClass));

		if(sClass[0] == '\0') {
			LogMessage("Undefined class name in \"Player %s\"", sClass);
			continue;
		}

		if(StrEqual("flags", sAuth, false)) {
			auth = AuthOption_Flags;
		} else if(StrEqual("steam", sAuth, false)) {
			auth = AuthOption_Steam;
		} else {
			LogMessage("Unrecognized option in \"Player %s\"", sClass);
			continue;
		}
		KvGetString(kv, "attribute", sAttribute, sizeof(sAttribute));
		KvGetString(kv, "scale", sScale, sizeof(sScale));

		new Handle:datapack = CreateDataPack();
		// 1: Auth
		WritePackCell(datapack, auth);
		// 2: Auth Attribute
		WritePackString(datapack, sAttribute);
		// 3: Class Name
		WritePackString(datapack, sClass);
		// 4: Scale
		WritePackString(datapack, sScale);

		PushArrayCell(g_hAuthStack, datapack);
	} while(KvGotoNextKey(kv));

	return 0;
}

// Load config to turn file information into classes
LoadFileFromConfig(Handle:kv)
{
	new Handle:hPrecachedFiles = CreateArray();
	new String:sClass[50];
	new String:sVMT[PLATFORM_MAX_PATH];
	new String:sVTF[PLATFORM_MAX_PATH];
	
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

		new count = GetArraySize(g_hClasses);

		// Save VMT filepath
		new Handle:classPack = CreateDataPack();
		WritePackString(classPack, sVMT);

		PushArrayCell(g_hClasses, classPack);
		SetTrieValue(g_hClassIndexes, sClass, count);
	} while(KvGotoNextKey(kv));

	CloseHandle(hPrecachedFiles);

	return 0;
}

bool:ClassGiveModel(client, const String:class[], const String:scale[])
{
	new index;
	new String:filepath[PLATFORM_MAX_PATH];

	if(!GetTrieValue(g_hClassIndexes, class, index))	return false;
	new Handle:classPack = Handle:GetArrayCell(g_hClasses, index);
	ResetPack(classPack);
	ReadPackString(classPack, filepath, sizeof(filepath));

	// Delete an entity(if exists) first
	Entity_SafeDelete(g_Models[client]);

	g_Models[client] = CreateIcon(filepath, scale);

	if(g_Models[client] != -1) {
		PlaceAndBindIcon(client, g_Models[client]);
		return true;
	}
	
	return false;
}
