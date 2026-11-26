<?php
Dict::Add('ES CR', 'Spanish', 'Español, Castellano', array(
	'Class:Ticket/Attribute:tags' => 'Etiquetas',
	'Class:Ticket/Attribute:tags+' => 'Etiquetas del ticket. DEVOPS crea un PBI en el sprint actual de Azure DevOps.',
	'Class:Ticket/Attribute:devops_id' => 'PBI de Azure DevOps',
	'Class:Ticket/Attribute:devops_id+' => 'Número del elemento creado en Azure DevOps para este ticket.',
	'Class:Ticket/Attribute:devops_url' => 'Enlace al PBI',
	'Class:Ticket/Attribute:devops_url+' => 'Abre el PBI en Azure DevOps.',
	'Class:AsyncItopDevOps' => 'Envío a Azure DevOps (DEVOPS)',
	'Class:AsyncItopDevOps/Attribute:ticket_class' => 'Clase del ticket',
	'Class:AsyncItopDevOps/Attribute:ticket_id' => 'Ticket',
	'ItopDevOps:Log:Created' => 'PBI %1$s creado en Azure DevOps (%2$s): %3$s',
	'ItopDevOps:Log:Linked' => 'Este ticket ya tenía el PBI %1$s en Azure DevOps: %2$s',
	'ItopDevOps:Log:Failed' => 'No se pudo crear el PBI en Azure DevOps después de varios intentos: %1$s',
));
