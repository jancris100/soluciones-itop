<?php
Dict::Add('ES CR', 'Spanish', 'Español, Castellano', array(
	'Class:Ticket/Attribute:tags' => 'Etiquetas',
	'Class:Ticket/Attribute:tags+' => 'Etiquetas del ticket. KADSI crea un PBI en el sprint actual de Azure DevOps.',
	'Class:Ticket/Attribute:devops_id' => 'PBI de Azure DevOps',
	'Class:Ticket/Attribute:devops_id+' => 'Número del elemento creado en Azure DevOps para este ticket.',
	'Class:Ticket/Attribute:devops_url' => 'Enlace al PBI',
	'Class:Ticket/Attribute:devops_url+' => 'Abre el PBI en Azure DevOps.',
	'Class:AsyncKadsiDevOps' => 'Envío a Azure DevOps (KADSI)',
	'Class:AsyncKadsiDevOps/Attribute:ticket_class' => 'Clase del ticket',
	'Class:AsyncKadsiDevOps/Attribute:ticket_id' => 'Ticket',
	'KadsiDevOps:Log:Created' => 'PBI %1$s creado en Azure DevOps (%2$s): %3$s',
	'KadsiDevOps:Log:Linked' => 'Este ticket ya tenía el PBI %1$s en Azure DevOps: %2$s',
	'KadsiDevOps:Log:Failed' => 'No se pudo crear el PBI en Azure DevOps después de varios intentos: %1$s',
));
