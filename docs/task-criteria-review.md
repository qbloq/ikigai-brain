# Task Criteria — Critic Review

_Critic pass (gemini-2.5-flash) over 603 tasks from `task-criteria-full.json`._

## Summary

| Action | Count |
| --- | --: |
| ✅ keep | 1831 |
| ➖ drop | 1 |
| 🔄 remethod | 114 |
| ↳ of which resolvability flips (auto/llm → attested) | 72 |

Final criteria: **1945** (dropped 1).

## Flagged criteria

### 🔄 Re-methoded (114)

- **remethod llm→attested** · _VSL A/B Test Configuration_ — "The A/B test is correctly configured to split traffic 50%-50% between the original and the new VSL."  
  The A/B test configuration is likely within an opaque tool (e.g., VTurb) that an LLM cannot directly inspect. Verification requires human attestation of the configuration.
- **remethod llm→attested** · _VSL A/B Test Configuration_ — "The new VSL is correctly integrated and active within the A/B test setup."  
  Integration and activation within an A/B test setup (likely an opaque tool) cannot be directly verified by an LLM. It requires human attestation.
- **remethod llm→attested** · _Masterclass WhatsApp Communities_ — "The WhatsApp communities are correctly created and configured specifically for Masterclass lead capture."  
  WhatsApp communities are an opaque platform. An LLM cannot directly inspect their internal configuration to verify correct creation and setup for lead capture. This requires human attestation.
- **remethod llm→attested** · _Masterclass WhatsApp Communities_ — "The created communities are ready to receive new members and function as intended for the Masterclass."  
  Verifying that WhatsApp communities are 'ready to receive new members and function as intended' requires inspection of an opaque platform, which an LLM cannot do directly. This needs human attestation.
- **remethod automated→llm** · _Videos completos_ — "The video files are of a valid video format and have good resolution (implied by file size)."  
  The 'automated' method with 'mime_in' only verifies the video format, not the 'good resolution' aspect. 'Good resolution' is a subjective quality that would be better assessed by an LLM (if it can process video content) or manually.
- **remethod test→attested** · _Biturbo A/B Test Setup_ — "The A/B testing for VSLs is correctly configured in Biturbo."  
  Biturbo is an opaque tool not integrated for direct inspection. An automated 'test' or 'computed_check' is not resolvable. Remethod to 'attested' for human confirmation.
- **remethod llm→attested** · _Mensaje a David_ — "El mensaje incluye información relevante y actualizada sobre el progreso de los videos."  
  The content of a message sent to an external recipient is typically not directly inspectable by an LLM unless the message itself is captured as an explicit output artifact. The act of sending is an opaque human action.
- **remethod llm→attested** · _Audios enviados_ — "Los audios enviados son los correctos para los grupos de la masterclass."  
  The content of audios sent to an external recipient is typically not directly inspectable by an LLM unless the audios themselves are captured as explicit output artifacts. The act of sending is an opaque human action.
- **remethod llm→attested** · _VSL entregado a Luisa_ — "El VSL entregado es el 'nuevo VSL' mencionado en la tarea."  
  The content of the VSL delivered to an external recipient is typically not directly inspectable by an LLM unless the VSL itself is captured as an explicit output artifact. The act of delivery is an opaque human action.
- **remethod llm→attested** · _Confirmación estado VSL_ — "La confirmación es clara y responde directamente a si el VSL está rodando."  
  The content of a confirmation, if it's part of a 'message_or_communication' output type, is typically not directly inspectable by an LLM unless the confirmation text itself is captured as an explicit output artifact. The act of confirming is an opaque human action.
- **remethod llm→attested** · _Instagram Stories_ — "The content of the Instagram stories is relevant and engaging for increasing audience capture for the masterclass."  
  Instagram stories are published on an opaque platform not directly inspectable by an LLM. Verification requires human attestation or manual review.
- **remethod llm→attested** · _Instagram Stories_ — "The Instagram stories were published today or over the weekend as requested."  
  Publication date of Instagram stories on an opaque platform cannot be directly verified by an LLM. Verification requires human attestation.
- **remethod llm→attested** · _New Ad Campaigns_ — "The launched campaigns demonstrate a broader segmentation strategy as intended to increase lead volume."  
  Ad campaign segmentation details are typically within opaque ad platforms not directly inspectable by an LLM. Verification requires human attestation.
- **remethod llm→attested** · _New Ad Campaigns_ — "The campaigns are correctly configured and targeted to effectively increase lead volume."  
  Ad campaign configuration and targeting details are typically within opaque ad platforms not directly inspectable by an LLM. Verification requires human attestation.
- **remethod llm→attested** · _Compiled Story Responses_ — "The compiled responses accurately reflect the content and context of the responses received from Andrea's story sequences."  
  The deliverable is a message or communication that has been sent. An LLM cannot directly inspect the content of a sent message in an opaque system. Verification of content accuracy for a sent communication should be attested by the recipient or sender, aligning with the RESOLVABILITY RULE.
- **remethod llm→attested** · _Lista de anuncios enviada_ — "The sent list accurately identifies the winning ads for 'La Ciencia de la Abundancia' as per the project's criteria."  
  The deliverable is a message or communication that has been sent. An LLM cannot directly inspect the content of a sent message in an opaque system. Verification of content accuracy for a sent communication should be attested by the recipient or sender, aligning with the RESOLVABILITY RULE.
- **remethod llm→attested** · _Lead magnet con formulario_ — "El lead magnet incluye un formulario integrado para la recolección de datos de los interesados."  
  Verifying an 'integrated form for data collection' goes beyond simple text inspection by an LLM from a content draft. It implies checking functionality and actual integration, which requires human attestation on a live artifact or a dedicated test, not just LLM review of a draft.
- **remethod llm→attested** · _Sent Work Schedule_ — "The communication includes a clear and comprehensive work schedule for organizing service delivery."  
  Per the RESOLVABILITY RULE, an LLM cannot inspect the content of a 'message_or_communication' that has been 'sent' unless it's a directly accessible artifact. This is a real-world action that typically requires attestation.
- **remethod llm→manual** · _New VSL_ — "The VSL content is specifically for 'La Ciencia de la Abundancia' and functions effectively as a sales letter."  
  An LLM cannot directly inspect the content of a video asset to determine its specific content or effectiveness as a sales letter. This requires manual human review.
- **remethod llm→attested** · _Revised sales funnels_ — "The sales funnels accessible via the URL reflect the necessary changes discussed and agreed upon with Roberto."  
  An LLM cannot verify that the funnels reflect changes 'discussed and agreed upon with Roberto' as it cannot access the context of that discussion or the agreement itself. This requires human attestation.
- **remethod llm→attested** · _Funnels review feedback_ — "The feedback accurately summarizes the review with Roberto and details the changes implemented or recommended for the sales funnels."  
  An LLM cannot verify the accuracy of a summary of a discussion with Roberto as it does not have access to the discussion itself. This requires human attestation.
- **remethod llm→attested** · _VSL configurado en Biturbo con A/B testing_ — "The new VSL includes the specified new hooks and testimonials."  
  The VSL content, once uploaded to the opaque Biturbo platform, cannot be directly inspected by an LLM. Verification requires human attestation.
- **remethod test→attested** · _WhatsApp Admin Added_ — "David's support number has been successfully added as an administrator to the WhatsApp Masterclass community."  
  Adding an administrator to a WhatsApp community is an action within an opaque system not typically accessible via API for automated checks. Verification requires attestation from a human who can confirm the change, adhering to the RESOLVABILITY RULE.
- **remethod llm→attested** · _Decision on Mari's Proposal_ — "Se ha tomado una decisión clara y final sobre la propuesta de Mari para liderar la implementación del nuevo sistema."  
  An LLM cannot directly verify that a 'decision has been taken' without a specific, inspectable artifact (e.g., a written record, an email). This is a real-world human action/outcome, falling under the RESOLVABILITY RULE.
- **remethod llm→attested** · _Decision on Mari's Proposal_ — "La decisión aborda tanto el rol de liderazgo propuesto como la solicitud de ajuste salarial de Mari."  
  An LLM cannot directly verify the content of a 'decision' without a specific, inspectable artifact. This is a real-world human action/outcome, falling under the RESOLVABILITY RULE.
- **remethod llm→attested** · _Mari's Role Scope & Objectives_ — "Se han definido los KPIs y el alcance para el nuevo rol operativo de Mari."  
  An LLM cannot directly verify that KPIs and scope 'have been defined' without a specific, inspectable artifact (e.g., a document). This is a real-world human action/outcome, falling under the RESOLVABILITY RULE.
- **remethod llm→attested** · _Mari's Role Scope & Objectives_ — "El alcance y los objetivos definidos para el rol de Mari son claros, específicos y accionables."  
  An LLM cannot directly verify the quality of KPIs and scope 'defined' without a specific, inspectable artifact. This is a real-world human action/outcome, falling under the RESOLVABILITY RULE.
- **remethod llm→attested** · _Resultados de la encuesta_ — "El informe contiene datos reales recopilados de las encuestas a la comunidad."  
  An LLM cannot definitively verify if the data is 'real' or 'collected from community surveys' without access to the source system or external attestation. This requires human confirmation of the data's origin and authenticity.
- **remethod llm→attested** · _Tablero de tareas en Notion_ — "El tablero de Notion contiene todas las tareas definidas para el proyecto."  
  An LLM cannot reliably verify the completeness of tasks within an opaque tool like Notion without direct API integration. This requires human attestation or manual verification.
- **remethod automated→attested** · _Videos Sent for Editing_ — "The sent videos are in a common video format acceptable for editing."  
  The criterion refers to properties of 'sent videos'. If the system does not have direct access to inspect the actual files that were sent to an external editor (an opaque tool or real-world action), automated checks are not resolvable. This falls under the Resolvability Rule, requiring 'attested'.
- **remethod automated→attested** · _Videos Sent for Editing_ — "The sent video files have a minimum size of 5MB each."  
  The criterion refers to properties of 'sent videos'. If the system does not have direct access to inspect the actual files that were sent to an external editor (an opaque tool or real-world action), automated checks are not resolvable. This falls under the Resolvability Rule, requiring 'attested'.
- **remethod llm→attested** · _Aligned content strategy_ — "The content strategy is clearly aligned with the new narrative and angles, as discussed with Sophie."  
  The criterion refers to a discussion with a specific person ('Sophie'), which is a real-world human action that cannot be verified by an LLM. It requires human attestation.
- **remethod llm→attested** · _Aligned strategy document_ — "The strategy documented is clearly aligned with Lucho and the commercial team for the new direction."  
  The criterion refers to alignment with specific individuals ('Lucho and the commercial team'), which implies a real-world human interaction that cannot be verified by an LLM. It requires human attestation.
- **remethod llm→attested** · _Tareas organizadas en Notion_ — "All tasks defined for the project are present in the Notion board/database."  
  Notion is an opaque tool. While the URL is reachable, an LLM cannot reliably parse and verify the content of a Notion board/database for completeness without specific API integration, which is not indicated. Verification of content presence should be 'attested'.
- **remethod llm→attested** · _Tareas organizadas en Notion_ — "The tasks within Notion are organized as specified (e.g., by status, priority, owner)."  
  Notion is an opaque tool. An LLM cannot reliably parse and verify the organization of tasks within a Notion board/database without specific API integration, which is not indicated. Verification of organization should be 'attested'.
- **remethod llm→attested** · _Guidance for Editing Team_ — "The communicated guidance must be strategic and clearly indicate which specific videos to use for content structures."  
  The content of a 'message or communication' is often not directly inspectable by an LLM validator if it's an action rather than a concrete artifact. This falls under the 'opaque tool' or 'real-world human action' rule, requiring attestation.
- **remethod llm→manual** · _Meeting Schedule_ — "The scheduled meetings must be more frequent than previous campaign review meetings."  
  An LLM cannot independently verify if the new schedule is 'more frequent than previous campaign review meetings' without access to the previous meeting schedule, which is external context not typically provided to the LLM validator for a single artifact. This requires human judgment or access to historical data.
- **remethod llm→attested** · _Análisis de tipo de leads_ — "El análisis refleja una revisión de las respuestas de las 70 personas registradas en el funnel."  
  The LLM cannot verify the accuracy of the claim that 70 responses were reviewed against the source data if the 'funnel gamificado' is an opaque tool. A human attestation is required to confirm the review of the specified number of responses.
- **remethod llm→manual** · _Adjusted VSL_ — "El VSL de David incluye los nuevos testimonios integrados y los antiguos han sido reemplazados según lo solicitado."  
  An LLM cannot directly verify the content of a video asset to confirm specific testimonials have been integrated or replaced. This requires human review.
- **remethod llm→manual** · _Recorded reels_ — "Los reels grabados incluyen testimonios y anuncios según lo solicitado."  
  An LLM cannot directly verify the content of a video asset to confirm it includes specific types of content like testimonials and advertisements. This requires human review.
- **remethod llm→attested** · _Validated Metricans Dashboard_ — "The formulas within the Metricans dashboard are correctly implemented and validated, ensuring accurate data representation."  
  An LLM cannot directly inspect the internal formulas of an opaque analytics dashboard like Metricans. This requires manual verification or attestation from the person who performed the review.
- **remethod llm→attested** · _Validated Metricans Dashboard_ — "The dashboard content reflects the finalized review of formulas."  
  An LLM cannot reliably verify that dashboard content reflects a finalized review of formulas in an opaque tool like Metricans. This requires manual verification or attestation.
- **remethod llm→attested** · _June Ad Structure_ — "The advertising campaign structure for June is complete and fully defined."  
  An LLM cannot directly inspect the completeness and definition of an advertising campaign structure within an opaque ad platform. This requires attestation from the person who built it or manual review.
- **remethod llm→attested** · _June Ad Structure_ — "The ad structure is based on the identified winning ads and adheres to the previous strategy."  
  An LLM cannot directly verify adherence to winning ads and previous strategy within an opaque ad platform. This requires attestation or manual review.
- **remethod test→attested** · _Flujos de automatización en ManyChat_ — "The ManyChat automation flows for audio cuts are configured and active."  
  ManyChat is an opaque tool explicitly mentioned in the RESOLVABILITY RULE. Direct automated verification ('test' with 'computed_check') of internal configuration is not possible without specific integration. It should be remethoded to 'attested'.
- **remethod llm→manual** · _Gráfico de escalera de valor_ — "The graphic visually represents Andrea's value ladder clearly and accurately."  
  An LLM cannot reliably verify the visual representation and accuracy of an image asset. This requires manual human inspection as per the Resolvability Rule.
- **remethod test→attested** · _Tags configurados en ManyChat/GoHighLevel_ — "The tags 'problema', 'solución', '10x solución', and 'agendamiento' are defined and configured in ManyChat or GoHighLevel."  
  ManyChat/GoHighLevel are considered opaque tools for direct programmatic inspection of internal configurations like tags, unless a specific API integration is confirmed. The 'computed_check' validator_id does not sufficiently imply such an integration for an opaque tool. Therefore, verification should be attested.
- **remethod test→attested** · _Setters capacitados_ — "Setters demonstrate proficiency in using ManyChat and manually tagging leads by stages."  
  Demonstrating proficiency in using a tool and performing a manual process is a real-world human action that cannot be reliably verified by a 'computed_check' without a highly specific and integrated testing environment, which is not implied. It should be attested by an observer or manager.
- **remethod llm→attested** · _Historias publicadas_ — "The published stories align with the concept of 'agitation stories' as understood by the team."  
  The 'published stories' likely reside in an opaque external system (e.g., social media, blog) that an LLM cannot directly inspect. This falls under the RESOLVABILITY RULE for opaque tools, requiring 'attested' verification.
- **remethod test→attested** · _ManyChat implementado_ — "ManyChat has been successfully configured and integrated for setters' communication."  
  The criterion refers to the successful configuration and integration of ManyChat. As per the RESOLVABILITY RULE, ManyChat's correctness (which 'successfully configured' implies) is considered an opaque deliverable. An automated 'test' via 'computed_check' is unlikely to directly verify the internal state of ManyChat without deep integration, making 'attested' a more appropriate method for verifying the outcome of the configuration.
- **remethod test→attested** · _Tags definidos y configurados_ — "The specified tags for lead awareness stages (problema, solución, 10x solución, agendamiento) exist in ManyChat/GoHighLevel."  
  ManyChat/GoHighLevel are opaque tools; automated/test checks are not possible without integration. Verification requires manual attestation.
- **remethod test→attested** · _Tags definidos y configurados_ — "The tags are correctly configured and associated with their respective lead awareness stages in ManyChat/GoHighLevel."  
  ManyChat/GoHighLevel are opaque tools; automated/test checks are not possible without integration. Verification requires manual attestation.
- **remethod llm→attested** · _Calendario de reuniones_ — "The frequency of the scheduled meetings is demonstrably higher than previous review and optimization meetings."  
  An LLM cannot access historical meeting data to compare frequencies, as this requires external context not available to the LLM. 'Attested' is more appropriate for a human to verify this comparison.
- **remethod llm→test** · _Formulario de leads actualizado_ — "The disclaimer/checkbox is correctly implemented and functional within the form."  
  An LLM cannot verify the functionality of a checkbox or form element, as this requires dynamic interaction (e.g., clicking, submitting), not static content analysis. A 'test' method is more appropriate for verifying functionality.
- **remethod llm→manual** · _New Ad Videos_ — "The video content includes testimonials and is suitable for use as ad hooks and reels."  
  An LLM cannot directly inspect video content to verify testimonials or suitability for ad hooks/reels. This requires human review.
- **remethod llm→attested** · _Contenido orgánico producido_ — "The volume and nature of the produced content demonstrate an effort towards the goal of a minimum of one reel per day."  
  An LLM inspecting a 'content_draft' cannot reliably verify a daily production rate ('minimum of one reel per day'). This requires tracking over time or human attestation of ongoing production, or integration with a system that tracks published content.
- **remethod llm→attested** · _Landing page para captación de leads_ — "The landing page successfully sends captured lead data directly to WhatsApp with the adapted offer."  
  An LLM cannot verify the successful sending of data to an external, potentially opaque system like WhatsApp without direct integration or a functional test. This requires confirmation of a real-world action, which is best verified by 'attested' or 'test'.
- **remethod manual→attested** · _Proposal and salary decision_ — "A decision has been made regarding Mari's proposal to lead the implementation and her salary adjustment request."  
  Making a decision is a real-world human action. Per the RESOLVABILITY RULE, real-world human actions should be verified by attestation rather than a generic manual check, unless a specific artifact is linked for manual inspection.
- **remethod attested→automated** · _Editor recommendation_ — "The recommendation or decision is documented and accessible."  
  If the recommendation is 'documented', it implies an artifact that can be checked for existence and accessibility via an automated method (e.g., checking a file path or URL). 'Attested' is for things that cannot be directly inspected by the system.
- **remethod llm→attested** · _Optimized Ad Campaigns_ — "The ad campaigns show evidence of optimization, specifically that low-performing ads have been turned off and new ads have been produced based on successful angles and formats."  
  The verification method 'llm' is not suitable for inspecting the state and actions within an opaque ad campaign management platform. An LLM cannot directly verify that specific ads were turned off or new ones produced based on performance. This requires human attestation or a direct API integration which is not implied.
- **remethod llm→manual** · _High-Quality Old Videos_ — "The video files are of high quality and do not show pixelation issues, suitable for new structures or edits."  
  Assessing video quality for pixelation and suitability for editing is a highly visual and subjective task that an LLM may not reliably perform without specialized tools or human oversight. A manual review is more appropriate for this type of quality check.
- **remethod test→attested** · _Automatización de audios en ManyChat_ — "La automatización para cortar audios está configurada en ManyChat."  
  ManyChat is an opaque tool; verifying internal configuration via 'test' without explicit integration is not feasible. It should be attested by a human.
- **remethod test→attested** · _Automatización de audios en ManyChat_ — "La automatización de corte de audios en ManyChat funciona correctamente según lo esperado."  
  ManyChat is an opaque tool; verifying functionality via 'test' without explicit integration is not feasible. It should be attested by a human.
- **remethod llm→attested** · _Organic Content (Reels/Stories)_ — "The volume of content provided aligns with the goal of at least one reel per day and intentional story sequences."  
  The criterion 'at least one reel per day' refers to a continuous volume of content over time, which cannot be verified by an LLM inspecting a single 'content_draft'. This requires monitoring real-world actions or an attestation of the achieved volume.
- **remethod llm→attested** · _Reviewed Dashboard Formulas_ — "The formulas within the Metricans dashboard have been finalized and reviewed."  
  An LLM cannot reliably inspect the internal formulas of a Metricans dashboard unless there's a specific API integration for formula review, which is not implied. This is an opaque tool for LLM inspection, requiring human attestation.
- **remethod llm→manual** · _Chat conversation to lead ratio_ — "The report accurately calculates and presents the number of chat conversations required to generate 25 organic leads."  
  An LLM can read the report, but it cannot independently verify the accuracy of calculations against external, real-world data sources (like actual chat logs and lead records) that are not part of the provided artifact. This requires human verification against the source systems.
- **remethod llm→attested** · _Optimized taskboards_ — "The taskboards show clear evidence of optimization for project management, improving efficiency or clarity."  
  An LLM cannot reliably inspect a dynamic 'taskboard system' for 'optimization' via a URL without specific integration, as it's likely an opaque tool. This requires human judgment.
- **remethod llm→attested** · _Optimized taskboards_ — "The content at the URL is indeed a taskboard system used for project management."  
  An LLM cannot reliably determine if a complex, potentially interactive web application at a URL is 'indeed a taskboard system' without specific integration. This requires human judgment.
- **remethod llm→attested** · _Optimized Ad Campaigns_ — "The ad campaigns show evidence of optimization based on successful angles and formats, aiming to increase precision."  
  LLM cannot directly inspect ad campaign performance or optimization actions within an opaque ad platform; this requires attestation of actions taken or results observed.
- **remethod llm→attested** · _WhatsApp Lead Flow_ — "The WhatsApp message sent to leads includes the adapted offer."  
  An LLM cannot directly inspect the content of a WhatsApp message sent to a lead. This requires access to an opaque system or observation of a real-world communication.
- **remethod llm→attested** · _Follow-up Message_ — "The message clearly requests an update on the delivery of the free YouTube course."  
  An LLM cannot directly inspect the content of a message that has been sent to a recipient without access to the message content as an artifact.
- **remethod llm→attested** · _Aligned Data_ — "The metrics and data are demonstrably aligned across Paralelo, Excel, and Go High Level systems."  
  An LLM cannot directly access and compare live data or configurations across multiple distinct and potentially opaque systems like Paralelo, Excel, and Go High Level to verify alignment. This requires integration or human verification.
- **remethod attested→automated** · _14 Raw Reels_ — "Exactly 14 video files are present for the reels."  
  If the video files are inspectable (as implied by subsequent criteria), then counting them is an automated task, not something that requires attestation.
- **remethod llm→manual** · _New Optimized Ad Creatives_ — "The new ad creatives are based on successful angles and formats that have previously shown results, as per the task objective."  
  An LLM cannot independently verify if ad creatives are based on 'successful angles and formats that have previously shown results' without access to external performance data or a clear, verifiable definition of these successful elements. This requires human judgment against strategic context.
- **remethod llm→attested** · _Estructura y estrategia de oferta definida_ — "Se ha definido la estructura y estrategia completa de la oferta de Andrea (VSL, low ticket, etc.)."  
  The output type 'decision' does not inherently provide an inspectable artifact for an LLM to verify. Verifying that a decision has been made and communicated typically requires human attestation.
- **remethod llm→attested** · _Estructura y estrategia de oferta definida_ — "La estructura y estrategia definida es coherente con los objetivos de la oferta de Andrea."  
  The output type 'decision' does not inherently provide an inspectable artifact for an LLM to verify the coherence of the defined structure and strategy. This typically requires human attestation or a manual review of the outcome.
- **remethod attested→automated** · _New Reels_ — "The volume of new reels meets the minimum requirement of at least one reel per day for the specified period."  
  The volume of created files over a period can be programmatically checked if the files are stored in an accessible location, making 'automated' a more precise verification method than 'attested'.
- **remethod llm→attested** · _Tags configurados_ — "The configured tags accurately represent the specified lead awareness stages (problema, solución, 10x solución, agendamiento)."  
  ManyChat/GoHighLevel are opaque tools. An LLM cannot directly inspect their internal configuration to verify the accuracy of tags. Verification requires human access or specific integration, making 'attested' more appropriate.
- **remethod llm→attested** · _Follow-up Message_ — "The sent message explicitly requests the 'Reels' and 'YouTube content' from David."  
  The 'RESOLVABILITY RULE' states that 'automated' or 'llm' is only valid if the artifact can actually be inspected. If the act of sending the message (Criterion 0) is 'attested' because the message itself is not an inspectable artifact for the system, then an LLM cannot verify its content. This should be remethoded to 'attested' as a human action/confirmation.
- **remethod llm→manual** · _Chat-to-Lead Analysis_ — "The report accurately details the number of chat conversations required to generate 25 organic leads."  
  An LLM can only verify if the report states a number. It cannot verify if that number is factually accurate without access to the underlying chat and lead data, which is not implied to be available to the LLM. Manual review is required to cross-reference with actual records.
- **remethod llm→manual** · _Explanatory Note on MetaTrader Algorithm_ — "The explanation is clear, accurate, and understandable."  
  An LLM can assess clarity and understandability. However, verifying the factual accuracy of a technical explanation of a complex algorithm requires expert knowledge or access to authoritative technical documentation, which is not implied to be available to the LLM. Manual review by an expert is needed for accuracy.
- **remethod llm→manual** · _Cleaned Sales Report_ — "The report confirms that duplicate entries have been removed from the sales data."  
  An LLM can only confirm if the report states that duplicates were removed. It cannot verify if duplicates were actually removed from the underlying sales data without access to that data and the ability to perform data integrity checks. Manual verification of the data cleaning process or the underlying data is required.
- **remethod llm→automated** · _Cleaned Sales Data_ — "The spreadsheet data for March, April, and May has no duplicate entries."  
  Checking for duplicate entries in a spreadsheet is a precise, programmatic data integrity task. While an LLM can process tabular data, an automated script or tool is more reliable and efficient for this type of verification.
- **remethod llm→attested** · _Follow-up communication_ — "The communication clearly requested an update or prompt delivery of the YouTube course."  
  The verification_method 'llm' is not appropriate. If the communication itself is not an inspectable artifact (as implied by the previous criterion's 'attested' method for sending the message), an LLM cannot verify its content. This falls under the RESOLVABILITY RULE for opaque tools/actions.
- **remethod llm→attested** · _AI ads delivered to David_ — "The delivered ads are identifiable as 'AI ads' as per the task description."  
  The verification method 'llm' is inappropriate. The act of 'delivering ads to David' implies a human action or communication within an opaque system (e.g., email, internal messaging). The system cannot directly inspect the content of the ads after they are 'delivered' to David. This falls under the RESOLVABILITY RULE for opaque tools/actions, requiring 'attested' verification.
- **remethod llm→attested** · _Communication Summary_ — "The communication summary accurately reflects the discussion and decisions made with Andrés regarding Andrea's offer structure and strategy."  
  The LLM cannot verify the accuracy of a communication summary against a real-world discussion with Andrés, as the discussion itself is a real-world human action and not an inspectable artifact. This requires attestation.
- **remethod llm→attested** · _Communication Summary_ — "The summary includes all key points and decisions from the communication with Andrés about Andrea's offer (VSL, low ticket, etc.)."  
  The LLM cannot verify the completeness of a communication summary against all key points and decisions from a real-world discussion with Andrés, as the discussion itself is a real-world human action and not an inspectable artifact. This requires attestation.
- **remethod llm→manual** · _Weekly Billing Objectives_ — "The established weekly billing objectives are realistic and actionable for the closers."  
  Evaluating whether objectives are 'realistic and actionable' requires external business context, domain expertise, and potentially performance data that an LLM cannot access or verify from the provided text artifact alone. This is a subjective business judgment best made manually.
- **remethod llm→attested** · _Posts 'anzuelo' fijados_ — "Three 'anzuelo' (hook) posts have been created and are live."  
  Verifying if posts are 'live' on a social media profile (an opaque platform) is a real-world check, not directly inspectable by an LLM without specific integration. Per RESOLVABILITY RULE, remethod to 'attested'.
- **remethod automated→attested** · _Historias publicadas/borrador_ — "Las historias de David y Andrea existen como publicadas o guardadas como borrador en la plataforma."  
  The platform where stories are published or drafted is likely an opaque tool not directly accessible for automated artifact existence checks. Automated verification is not resolvable per the RESOLVABILITY RULE.
- **remethod llm→attested** · _Historias publicadas/borrador_ — "El contenido de las historias es relevante para David y Andrea y es adecuado para su publicación o borrador."  
  The LLM cannot directly inspect content within an opaque platform. LLM verification is not resolvable per the RESOLVABILITY RULE.
- **remethod llm→attested** · _Información consolidada_ — "The content of the document accurately and completely consolidates the information regarding automated audios with ManyChat, as discussed with Santi."  
  The LLM cannot verify the accuracy and completeness of the document against an uninspectable discussion with Santi. This requires human attestation of the content's alignment with the discussion.
- **remethod llm→attested** · _Standardized discount definition_ — "The defined discount is clearly standardized and applicable across relevant programs."  
  The output_type 'decision' is not an inspectable artifact for an LLM to evaluate its quality ('standardized' and 'applicable'). Verification requires human attestation or access to an external system/documentation not specified as inspectable, falling under the RESOLVABILITY RULE.
- **remethod llm→attested** · _Implemented Hook Posts_ — "The content of the three posts creates a sales context as intended."  
  The posts are implemented on David's profile, implying a live social media platform. If this platform is an opaque tool not integrated for direct LLM inspection, an 'llm' verification is not resolvable. Remethod to 'attested' for human verification of content context.
- **remethod test→attested** · _ManyChat Automation_ — "The ManyChat automation for new followers on David's profile is implemented."  
  ManyChat is an opaque tool not integrated for automated inspection. Verification of implementation should be attested by a human.
- **remethod test→attested** · _Audio System_ — "The audio system is implemented and integrated into the CTO process stages."  
  If the audio system implementation is within an opaque tool or system not integrated for automated inspection, 'test' without a specific validator is not resolvable. Verification should be attested by a human.
- **remethod llm→attested** · _Improved Gamified Funnel_ — "The gamified funnel has been enhanced with new images and voices that are 'dopamínicas' as per the task's objective."  
  Direct LLM inspection of subjective multimedia qualities ('dopamínicas' images and voices) within a potentially opaque external gamified funnel is not reliably resolvable. This requires human attestation.
- **remethod llm→attested** · _Improved Gamified Funnel_ — "The improvements to the gamified funnel are engaging and contribute to a more 'dopamínica' user experience."  
  Direct LLM assessment of subjective user experience qualities ('engaging', 'dopamínica user experience') within a potentially opaque external gamified funnel is not reliably resolvable. This requires human attestation.
- **remethod test→attested** · _CTO ManyChat automation_ — "The ManyChat automation for welcome messages is configured and active."  
  ManyChat is an opaque tool; direct automated verification of its internal configuration and activity via 'computed_check' is not resolvable. Remethod to 'attested' for human verification.
- **remethod test→attested** · _CTO ManyChat automation_ — "The ManyChat automation for qualification is configured and active."  
  ManyChat is an opaque tool; direct automated verification of its internal configuration and activity via 'computed_check' is not resolvable. Remethod to 'attested' for human verification.
- **remethod test→attested** · _CTO ManyChat automation_ — "The ManyChat automation for agenda confirmation is configured and active."  
  ManyChat is an opaque tool; direct automated verification of its internal configuration and activity via 'computed_check' is not resolvable. Remethod to 'attested' for human verification.
- **remethod llm→attested** · _Updated VSL button_ — "The VSL button is re-positioned directly below the video."  
  The VSL configuration is likely within an opaque system (e.g., VTurb) that an LLM cannot directly inspect. Verification requires human attestation.
- **remethod llm→attested** · _Updated VSL button_ — "The VSL button has been made visually larger than its previous size."  
  The VSL configuration is likely within an opaque system (e.g., VTurb) that an LLM cannot directly inspect. Verification requires human attestation.
- **remethod llm→attested** · _New School community_ — "The School community is clearly identified as being for Andrea's Premium offer."  
  Verifying the content and identification within a 'School' community page may require access beyond what an LLM can reliably inspect, especially if it's behind a login or requires specific context. Human attestation is more appropriate.
- **remethod llm→attested** · _Implemented ManyChat automation_ — "The ManyChat automation aligns with the specified requirements for David's account."  
  ManyChat is an opaque system that an LLM cannot directly inspect to verify alignment with requirements. Verification requires human attestation.
- **remethod llm→attested** · _Historias de Instagram publicadas_ — "The published Instagram stories are new and relevant to the social funnel as intended by the task."  
  Instagram stories are ephemeral and live in an opaque platform. Direct LLM verification of content, 'newness', and relevance on the live platform is not reliably resolvable without specific integration. This should be attested by a human.
- **remethod llm→attested** · _Anuncios nuevos publicados_ — "The published ads are new and align with the task's intent for 'ads nuevos'."  
  Published ads live in opaque ad platforms. Direct LLM verification of 'newness' and 'publication' status on the live platform is not reliably resolvable without specific integration. This should be attested by a human.
- **remethod automated→test** · _Conexión de checkout verificada_ — "The webhook connection between Andrea's checkout and GoHighLevel automations has been successfully tested and verified as working."  
  The criterion describes a system/config change (webhook connection) that needs to be verified as working. According to the RESOLVABILITY RULE, such a check should use the 'test' method.
- **remethod automated→test** · _Cuenta real de Andrea activada_ — "Andrea's real account, including the new checkout and funnel, has been successfully activated."  
  Activating an account with a new checkout and funnel is a system/config change. According to the RESOLVABILITY RULE, such a check should use the 'test' method.
- **remethod test→attested** · _Agente de IA para precalificación_ — "ManyChat has been configured to implement an AI agent for lead pre-qualification."  
  ManyChat is an opaque tool not integrated. Verifying its configuration directly via 'test' is not possible without integration. According to the RESOLVABILITY RULE, for opaque tools, the method should be 'attested'.
- **remethod test→attested** · _Agente de IA para precalificación_ — "The AI agent is configured to pre-qualify leads from Instagram."  
  ManyChat is an opaque tool not integrated. Verifying its configuration directly via 'test' is not possible without integration. According to the RESOLVABILITY RULE, for opaque tools, the method should be 'attested'.
- **remethod test→attested** · _Agente de IA para precalificación_ — "The AI agent is configured to pre-qualify leads from WhatsApp."  
  ManyChat is an opaque tool not integrated. Verifying its configuration directly via 'test' is not possible without integration. According to the RESOLVABILITY RULE, for opaque tools, the method should be 'attested'.
- **remethod test→attested** · _Sistema de etiquetas y resúmenes_ — "A system for tagging leads has been configured within ManyChat."  
  ManyChat is an opaque tool not integrated. Verifying its configuration directly via 'test' is not possible without integration. According to the RESOLVABILITY RULE, for opaque tools, the method should be 'attested'.
- **remethod test→attested** · _Sistema de etiquetas y resúmenes_ — "A system for summarizing leads before transfer to a human setter has been configured within ManyChat."  
  ManyChat is an opaque tool not integrated. Verifying its configuration directly via 'test' is not possible without integration. According to the RESOLVABILITY RULE, for opaque tools, the method should be 'attested'.

### ➖ Dropped (1)

- _Taskboards optimizados_ — "The taskboards are demonstrably optimized for project management, improving clarity and efficiency."  
  This criterion is redundant with criterion 1, which directly asks for confirmation from a project manager. Additionally, 'llm' is an inappropriate method for verifying optimization of 'taskboards' which are typically in opaque project management tools not directly inspectable by an LLM.
