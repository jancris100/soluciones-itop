<?php
/**
 * KADSI → Azure DevOps
 *
 * Agrega a los tickets un campo de etiquetas ("tags") y, cuando un incidente queda con la etiqueta KADSI, envía sus
 * datos (por la cola asíncrona de iTop, con reintentos) a la Azure Function KadsiBridge, que crea el PBI en el sprint
 * actual. La respuesta (número y enlace del PBI) se guarda en el ticket.
 *
 * Configuración en conf/production/config-itop.php, sección 'kadsi-devops' de module_settings.
 */
SetupWebPage::AddModule(
	__FILE__,
	'kadsi-devops/1.0.0',
	array(
		'label' => 'KADSI → Azure DevOps',
		'category' => 'business',

		'dependencies' => array(
			'itop-tickets/2.4.0',
			'itop-incident-mgmt-itil/2.4.0',
		),
		'mandatory' => false,
		'visible' => true,
		'installer' => 'KadsiDevOpsInstaller',

		'datamodel' => array(
			'main.kadsi-devops.php',
		),
		'webservice' => array(),
		'data.struct' => array(),
		'data.sample' => array(),

		'doc.manual_setup' => '',
		'doc.more_information' => '',

		// Valores por defecto: se cambian en config-itop.php, nunca aquí.
		'settings' => array(
			// Dirección de la Function: https://<app>.azurewebsites.net/api/kadsi/pbi
			'function_url' => '',
			// Llave de la Function (x-functions-key). En producción, la llave de la Function del ambiente de la empresa.
			'function_key' => '',
			// Etiqueta que dispara la creación del PBI (código de la etiqueta en "Configuración de Etiquetas").
			'tag_code' => 'KADSI',
			// Campo de etiquetas de los tickets.
			'tag_attcode' => 'tags',
			// Clases de ticket que se envían.
			'classes' => array('Incident'),
			// Segundos máximos de espera por la Function.
			'timeout' => 30,
		),
	)
);

if (!class_exists('KadsiDevOpsInstaller'))
{
	/**
	 * Crea la etiqueta KADSI en el campo de etiquetas de los tickets si todavía no existe.
	 */
	class KadsiDevOpsInstaller extends ModuleInstallerAPI
	{
		public static function AfterDatabaseCreation(Config $oConfiguration, $sPreviousVersion, $sCurrentVersion)
		{
			$sTagClass = TagSetFieldData::GetTagDataClassName('Ticket', 'tags');
			$oSearch = DBObjectSearch::FromOQL("SELECT $sTagClass WHERE code = 'KADSI'");
			$oSet = new DBObjectSet($oSearch);
			if ($oSet->Count() == 0)
			{
				$oTag = MetaModel::NewObject($sTagClass);
				$oTag->Set('code', 'KADSI');
				$oTag->Set('label', 'KADSI');
				$oTag->Set('description', 'Escala el ticket al equipo de desarrollo: crea un PBI en el sprint actual de Azure DevOps.');
				$oTag->DBInsert();
			}
		}
	}
}
