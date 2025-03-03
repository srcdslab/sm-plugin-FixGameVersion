#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "FixGameVersion",
	author = "maxime1907",
	description = "Allows all client game versions",
	version = "1.0.0",
	url = ""
};

char g_sPatchNames[][] = {"nVersionCheck"};

Address g_aPatchedAddresses[sizeof(g_sPatchNames)];
int g_iPatchedByteCount[sizeof(g_sPatchNames)];
int g_iPatchedBytes[sizeof(g_sPatchNames)][128]; // Increase this if a PatchBytes value in gamedata exceeds 128

public void OnPluginStart()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "gamedata/FixGameVersion.games.txt");

	if (!FileExists(path))
		SetFailState("Can't find FixGameVersion.games.txt gamedata.");

	GameData gameData = LoadGameConfigFile("FixGameVersion.games");
	
	if (gameData == INVALID_HANDLE)
		SetFailState("Can't find FixGameVersion.games.txt gamedata.");

	ApplyPatches(gameData);

	delete gameData;
}

void ApplyPatches(GameData gameData)
{
	// Iterate our patch names (these are dependent on what's in gamedata)
	for (int i = 0; i < sizeof(g_sPatchNames); i++)
	{
		char patchName[256];
		Format(patchName, sizeof(patchName), g_sPatchNames[i]);

		// Get the location of this patches signature
		Address addr = gameData.GetMemSig(patchName);

		if (addr == Address_Null)
		{
			LogError("%s patch failed: Can't find %s address in gamedata.", patchName, patchName);
			continue;
		}

		char cappingOffsetName[256];
		Format(cappingOffsetName, sizeof(cappingOffsetName), "CappingOffset_%s", patchName);

		// Get how many bytes we should move forward from the signature location before starting patching
		int cappingOffset = gameData.GetOffset(cappingOffsetName);

		if (cappingOffset == -1)
		{
			LogError("%s patch failed: Can't find %s offset in gamedata.", patchName, cappingOffsetName);
			continue;
		}

		// Get patch location
		addr += view_as<Address>(cappingOffset);

		char patchBytesName[256];
		Format(patchBytesName, sizeof(patchBytesName), "PatchBytes_%s", patchName);

		Address patchBytesAddr = gameData.GetMemSig(patchBytesName);

		if (patchBytesAddr == Address_Null)
		{
			LogError("%s patch failed: Can't find patch %s in gamedata.", patchName, patchBytesName);
			continue;
		}

		char patchBytesLengthName[256];
		Format(patchBytesLengthName, sizeof(patchBytesLengthName), "PatchBytesLength_%s", patchName);

		int patchBytesLength = gameData.GetOffset(patchBytesLengthName);

		if (patchBytesLength == -1)
		{
			LogError("%s patch failed: Can't find %s offset in gamedata.", patchName, patchBytesLengthName);
			continue;
		}

		// Store this patches address and byte count as it's being applied for unpatching on plugin unload
		g_aPatchedAddresses[i] = addr;
		g_iPatchedByteCount[i] = patchBytesLength;

		// Iterate each byte we need to patch
		for (int j = 0; j < patchBytesLength; j++)
		{
			// Store the original byte here for unpatching on plugin unload
			g_iPatchedBytes[i][j] = LoadFromAddress(addr, NumberType_Int8);
			int patchByte = LoadFromAddress(patchBytesAddr, NumberType_Int8);

			LogMessage("patching with %x %x", patchByte, g_iPatchedBytes[i][j]);
			// NOP this byte
			StoreToAddress(addr, patchByte, NumberType_Int8);

			// Move on to next byte
			addr++;
			patchBytesAddr++;
		}
	}
}

public void OnPluginEnd()
{
	// Iterate our currently applied patches and get their location
	for (int i = 0; i < sizeof(g_aPatchedAddresses); i++)
	{
		Address addr = g_aPatchedAddresses[i];

		// Iterate the original bytes in that location and restore them (undo the NOP)
		for (int j = 0; j < g_iPatchedByteCount[i]; j++)
		{
			StoreToAddress(addr, g_iPatchedBytes[i][j], NumberType_Int8);
			addr++;
		}
	}
}