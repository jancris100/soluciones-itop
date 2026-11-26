<?php
Dict::Add('EN US', 'English', 'English', array(
	'Class:Ticket/Attribute:tags' => 'Tags',
	'Class:Ticket/Attribute:tags+' => 'Ticket tags. DEVOPS creates a PBI in the current Azure DevOps sprint.',
	'Class:Ticket/Attribute:devops_id' => 'Azure DevOps PBI',
	'Class:Ticket/Attribute:devops_id+' => 'Work item created in Azure DevOps for this ticket.',
	'Class:Ticket/Attribute:devops_url' => 'PBI link',
	'Class:Ticket/Attribute:devops_url+' => 'Opens the PBI in Azure DevOps.',
	'Class:AsyncItopDevOps' => 'Azure DevOps sync (DEVOPS)',
	'Class:AsyncItopDevOps/Attribute:ticket_class' => 'Ticket class',
	'Class:AsyncItopDevOps/Attribute:ticket_id' => 'Ticket',
	'ItopDevOps:Log:Created' => 'PBI %1$s created in Azure DevOps (%2$s): %3$s',
	'ItopDevOps:Log:Linked' => 'This ticket already had PBI %1$s in Azure DevOps: %2$s',
	'ItopDevOps:Log:Failed' => 'The PBI could not be created in Azure DevOps after several attempts: %1$s',
));
