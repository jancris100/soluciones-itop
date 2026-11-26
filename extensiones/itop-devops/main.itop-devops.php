<?php
/**
 * iTop → Azure DevOps: detecta tickets con la etiqueta DEVOPS y los envía a la Azure Function ItopDevOpsBridge.
 *
 * Flujo:
 *  1. Al crear o modificar un ticket (ItopDevOpsObjectExtension), si tiene la etiqueta DEVOPS, todavía no tiene PBI
 *     y no hay un envío pendiente, se encola un AsyncItopDevOps. Guardar el ticket nunca espera a Azure.
 *  2. El cron de iTop (webservices/cron.php, tarea ExecAsyncTask) procesa la cola: llama a la Function, que crea el
 *     PBI en el sprint actual (o devuelve el que ya existía) y responde número, enlace y sprint.
 *  3. Se guardan devops_id y devops_url en el ticket y una nota en su registro privado.
 *     Los errores se reintentan según 'async_task_retries' de la configuración.
 */

/** Utilidades y configuración del módulo. */
class ItopDevOps
{
	const MODULE = 'itop-devops';

	public static function Setting($sName, $default = null)
	{
		return MetaModel::GetModuleSetting(self::MODULE, $sName, $default);
	}

	/** El ticket lleva la etiqueta configurada (DEVOPS) y es de una clase que se envía. */
	public static function IsTagged(DBObject $oObject)
	{
		$aClasses = (array)self::Setting('classes', array('Incident'));
		if (!in_array(get_class($oObject), $aClasses))
		{
			return false;
		}
		$sAttCode = self::Setting('tag_attcode', 'tags');
		if (!MetaModel::IsValidAttCode(get_class($oObject), $sAttCode))
		{
			return false;
		}
		$oTags = $oObject->Get($sAttCode);
		$aCodes = ($oTags instanceof ormTagSet) ? $oTags->GetValues() : array();
		return in_array(self::Setting('tag_code', 'DEVOPS'), $aCodes);
	}

	/** Encola el envío si corresponde: con etiqueta, sin PBI y sin otro envío pendiente para el mismo ticket. */
	public static function QueueIfNeeded(DBObject $oObject)
	{
		if (!self::IsTagged($oObject) || (string)$oObject->Get('devops_id') !== '')
		{
			return;
		}
		$sClass = get_class($oObject);
		$iId = (int)$oObject->GetKey();
		$oSearch = DBObjectSearch::FromOQL(
			"SELECT AsyncItopDevOps WHERE ticket_class = :class AND ticket_id = :id AND status IN ('planned', 'running')",
			array('class' => $sClass, 'id' => $iId)
		);
		$oPending = new DBObjectSet($oSearch);
		if ($oPending->Count() > 0)
		{
			return;
		}
		$oTask = MetaModel::NewObject('AsyncItopDevOps');
		$oTask->Set('ticket_class', $sClass);
		$oTask->Set('ticket_id', $iId);
		$oTask->DBInsert();
		IssueLog::Info("DEVOPS: envío a Azure DevOps encolado para $sClass #$iId");
	}

	/** Datos que se envían a la Function: solo lo necesario para el PBI. */
	public static function BuildPayload(DBObject $oTicket)
	{
		$sClass = get_class($oTicket);
		return array(
			'source' => 'itop',
			'ticketClass' => $sClass,
			'ticketId' => (int)$oTicket->GetKey(),
			'ref' => (string)$oTicket->Get('ref'),
			'title' => (string)$oTicket->Get('title'),
			'descriptionHtml' => (string)$oTicket->Get('description'),
			'priority' => MetaModel::IsValidAttCode($sClass, 'priority') ? (int)$oTicket->Get('priority') : null,
			'organization' => (string)$oTicket->Get('org_name'),
			'caller' => (string)$oTicket->Get('caller_name'),
			'service' => MetaModel::IsValidAttCode($sClass, 'service_name') ? (string)$oTicket->Get('service_name') : '',
			'ticketUrl' => ApplicationContext::MakeObjectUrl($sClass, $oTicket->GetKey(), null, false),
		);
	}

	/**
	 * Llama a la Function. Devuelve la respuesta decodificada; lanza excepción (que la cola reintenta) si falla.
	 * @throws Exception
	 */
	public static function CallFunction(array $aPayload)
	{
		$sUrl = (string)self::Setting('function_url', '');
		$sKey = (string)self::Setting('function_key', '');
		if ($sUrl === '' || $sKey === '')
		{
			throw new Exception("Falta configurar 'function_url' y 'function_key' de itop-devops en config-itop.php", 1);
		}

		$oCurl = curl_init($sUrl);
		curl_setopt_array($oCurl, array(
			CURLOPT_POST => true,
			CURLOPT_POSTFIELDS => json_encode($aPayload, JSON_UNESCAPED_UNICODE),
			CURLOPT_HTTPHEADER => array('Content-Type: application/json', 'x-functions-key: '.$sKey),
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_FOLLOWLOCATION => false,
			CURLOPT_TIMEOUT => (int)self::Setting('timeout', 30),
			CURLOPT_CONNECTTIMEOUT => 10,
		));
		$sBody = curl_exec($oCurl);
		$iHttp = (int)curl_getinfo($oCurl, CURLINFO_HTTP_CODE);
		$sCurlError = curl_error($oCurl);
		curl_close($oCurl);

		if ($sBody === false)
		{
			throw new Exception('No se pudo llamar a la Function: '.$sCurlError, 2);
		}
		$aBody = json_decode($sBody, true);
		if ($iHttp < 200 || $iHttp >= 300 || !is_array($aBody) || empty($aBody['workItemId']))
		{
			$sMessage = is_array($aBody) && isset($aBody['message']) ? $aBody['message'] : substr($sBody, 0, 300);
			throw new Exception("La Function respondió $iHttp: $sMessage", $iHttp);
		}
		return $aBody;
	}
}

/** Engancha la creación y modificación de tickets. */
class ItopDevOpsObjectExtension implements iApplicationObjectExtension
{
	public function OnIsModified($oObject)
	{
		return false;
	}

	public function OnCheckToWrite($oObject)
	{
		return array();
	}

	public function OnCheckToDelete($oObject)
	{
		return array();
	}

	public function OnDBUpdate($oObject, $oChange = null)
	{
		$this->SafeQueue($oObject);
	}

	public function OnDBInsert($oObject, $oChange = null)
	{
		$this->SafeQueue($oObject);
	}

	public function OnDBDelete($oObject, $oChange = null)
	{
	}

	/** Un problema al encolar nunca impide guardar el ticket. */
	private function SafeQueue($oObject)
	{
		if (!($oObject instanceof Ticket))
		{
			return;
		}
		try
		{
			ItopDevOps::QueueIfNeeded($oObject);
		}
		catch (Exception $e)
		{
			IssueLog::Error('DEVOPS: no se pudo encolar el envío a Azure DevOps: '.$e->getMessage());
		}
	}
}

/** Tarea de la cola asíncrona de iTop: un envío de un ticket a la Function. */
class AsyncItopDevOps extends AsyncTask
{
	public static function Init()
	{
		$aParams = array(
			'category' => 'core/cmdb',
			'key_type' => 'autoincrement',
			'name_attcode' => 'created',
			'state_attcode' => '',
			'reconc_keys' => array(),
			'db_table' => 'priv_async_itop_devops',
			'db_key_field' => 'id',
			'db_finalclass_field' => '',
		);
		MetaModel::Init_Params($aParams);
		MetaModel::Init_InheritAttributes();
		MetaModel::Init_AddAttribute(new AttributeString('ticket_class', array('allowed_values' => null, 'sql' => 'ticket_class', 'default_value' => '', 'is_null_allowed' => false, 'depends_on' => array())));
		MetaModel::Init_AddAttribute(new AttributeInteger('ticket_id', array('allowed_values' => null, 'sql' => 'ticket_id', 'default_value' => 0, 'is_null_allowed' => false, 'depends_on' => array())));
	}

	/**
	 * @return string Resultado para el registro de eventos
	 * @throws Exception Para que la cola reintente
	 */
	public function DoProcess()
	{
		$sClass = $this->Get('ticket_class');
		$iId = (int)$this->Get('ticket_id');
		$oTicket = MetaModel::GetObject($sClass, $iId, false, true /* AllowAllData: el cron no tiene contexto de usuario */);
		if ($oTicket === null)
		{
			return "El ticket $sClass #$iId ya no existe.";
		}
		if ((string)$oTicket->Get('devops_id') !== '')
		{
			return "El ticket $sClass #$iId ya tiene el PBI ".$oTicket->Get('devops_id').'.';
		}

		$aResult = ItopDevOps::CallFunction(ItopDevOps::BuildPayload($oTicket));

		$sWorkItem = (string)$aResult['workItemId'];
		$sUrl = (string)($aResult['url'] ?? '');
		$sIteration = (string)($aResult['iteration'] ?? '');
		$bCreated = !empty($aResult['created']);

		$oTicket->Set('devops_id', $sWorkItem);
		$oTicket->Set('devops_url', $sUrl);
		$oTicket->Set('private_log', $bCreated
			? Dict::Format('ItopDevOps:Log:Created', $sWorkItem, $sIteration, $sUrl)
			: Dict::Format('ItopDevOps:Log:Linked', $sWorkItem, $sUrl));
		$oTicket->DBUpdate();

		return "PBI $sWorkItem ".($bCreated ? 'creado' : 'ya existía')." para $sClass #$iId";
	}

	/** Agotados los reintentos: queda una nota en el ticket para que el agente lo sepa. */
	protected function OnDefinitiveFailure()
	{
		try
		{
			$oTicket = MetaModel::GetObject($this->Get('ticket_class'), (int)$this->Get('ticket_id'), false, true);
			if ($oTicket !== null)
			{
				$oTicket->Set('private_log', Dict::Format('ItopDevOps:Log:Failed', $this->Get('last_error')));
				$oTicket->DBUpdate();
			}
		}
		catch (Exception $e)
		{
			IssueLog::Error('DEVOPS: no se pudo anotar el fallo en el ticket: '.$e->getMessage());
		}
	}
}
