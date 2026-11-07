package main

// extraWorkspaceDefinition configures a picker entry outside the standard
// workspace roots. Add new entries here to make them available in the workspace
// picker and to prefix their Herdr workspace labels.
type extraWorkspaceDefinition struct {
	RelativePath string
	LabelPrefix  string
}

var extraWorkspaceDefinitions = []extraWorkspaceDefinition{
	{
		RelativePath: "nixconf",
		LabelPrefix:  "",
	},
	{
		RelativePath: ".pi",
		LabelPrefix:  "π",
	},
}
