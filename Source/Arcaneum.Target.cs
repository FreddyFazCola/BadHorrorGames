using UnrealBuildTool;
using System.Collections.Generic;

public class ArcaneumTarget : TargetRules
{
	public ArcaneumTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_4;

		ExtraModuleNames.AddRange(new string[] { "Arcaneum" });
	}
}
