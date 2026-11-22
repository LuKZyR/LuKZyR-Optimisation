# HelixFlux-Optimisation
Optimisation Windows sûre – by Lukzyr
====================================================
           LUKZYR OPTIMISATION  v0.1 bêta
=====================================================

VERSION BÊTA
  C'est la première version publique : v0.1 bêta (version interne 5.3). Elle a été
  testée, mais sur peu de PC différents. Si quelque chose cloche : Journal >
  « Exporter le journal », puis envoie le fichier avec une description du problème.
  Les numéros de version publics repartent de 0.1 (les anciennes « v5.x » étaient des
  versions de travail).

DÉMARRAGE
  1. Dézippe tout le dossier (ne lance pas depuis le zip).
  2. Double-clique sur "Lukzyr Optimisation.exe" (ou, en secours,
     sur "LANCER - Lukzyr Optimisation.bat").
  3. Accepte la demande administrateur.
  4. L'exe n'est pas signé numériquement : SmartScreen ou ton antivirus peuvent
     afficher un avertissement. SmartScreen : "Informations complémentaires" >
     "Exécuter quand même". Le code source de l'exe est dans assets\source-lanceur\
     (il ne fait que lancer scripts\Lukzyr-Optimisation.ps1 en administrateur).

L'INTERFACE (onglets en haut)
  TABLEAU DE BORD
    « Optimiser en 1 clic » : choisis un profil (Gaming max, Équilibré, PC portable ;
    PC portable est conseillé automatiquement si une batterie est détectée : il garde
    le plan d'alimentation équilibré et l'hibernation), puis clique sur le gros bouton
    OPTIMISER : point de restauration + sauvegarde des réglages + application du profil
    (le bouton pulse pendant l'exécution). Seuls les réglages du profil sont appliqués
    (pas les applis ni les pilotes).
    Jauges en direct (processeur, carte graphique, mémoire, disque C:).
    Alertes réelles : applis lourdes au démarrage, date de la dernière optimisation
    (+ lien « Tout annuler »), santé des disques / espace libre, nouvelle version.
    Tuiles vers chaque section.

  PERFORMANCE   Jeu (Mode Jeu, priorité aux jeux, planification GPU, souris sans
                accélération), processeur et alimentation (plan hautes performances,
                hibernation), mémoire et sécurité (VBS), affichage (transparence).
  NETTOYAGE     Windows plus léger (débloat, Copilot, OneDrive, Edge), confidentialité
                (télémétrie, Optimisation de la distribution), fichiers (temporaires,
                assistant de stockage, outil Nettoyage de disque).
  APPLICATIONS  Jeux : Steam, Epic Games, Ubisoft Connect, Rockstar Games, EA app,
                Battle.net, GOG Galaxy. Communication et musique : Discord, Spotify.
                Navigateurs : Brave. Création et utilitaires : OBS Studio, 7-Zip, VLC.
                Entretien : mise à jour des autres applis.
                (EA app, Battle.net, GOG Galaxy, 7-Zip, VLC, OBS : décochés par défaut.)
  SYSTÈME       Démarrage : applis lancées avec Windows (éditeur, impact estimé),
                activables / désactivables comme dans le Gestionnaire des tâches ;
                les logiciels de sécurité ne sont jamais modifiables.
                Réseau : DNS actuel ; Automatique (FAI), Cloudflare, Google ou Quad9
                (IPv4 + IPv6) ; « Vider le cache DNS ».
                Réparation et sécurité : TRIM des SSD, réparation DISM + SFC,
                « Tout annuler », Restaurer le système, Gestionnaire de périphériques,
                Redémarrer le PC.
  MATÉRIEL      Mon PC (composants détectés), Pilotes officiels, Santé (disques,
                espace libre, température, mémoire, alertes), Guide BIOS personnalisé
                pour TA carte mère (exporter, page support, redémarrer dans le BIOS ;
                rien n'est jamais modifié dans le BIOS ; texte du guide en français).
  JOURNAL       Ce qui se passe, en direct.
  PARAMÈTRES    (roue dentée) Thème clair, Langue FR / EN, Animations,
                Mise à jour de l'appli, À propos.

  Chaque option a un badge :
    SÛR        sans danger, remis par « Tout annuler »
    AVANCÉ     à comprendre avant (VBS, Copilot, OneDrive, réparation DISM/SFC)
    DÉFINITIF  ne peut pas être annulé (désinstallation d'Edge)
  Activer une option AVANCÉ ou DÉFINITIF à la main demande une confirmation, et le
  récapitulatif avant application les liste à part.

  Dans une section : active les interrupteurs voulus (clique n'importe où sur la
  carte), puis APPLIQUER (en bas). Une seule fenêtre récapitule ce qui va être fait.
  Tout se déroule en arrière-plan, sans fenêtre noire, et s'affiche dans Journal.
  Redémarre le PC à la fin.

TOUT ANNULER (bouton en bas de chaque section, Système > Réparation et sécurité,
              ou lien sur le Tableau de bord)
  Avant chaque application, la valeur D'ORIGINE de chaque réglage modifié est
  enregistrée dans C:\ProgramData\Lukzyr\sauvegarde-reglages.json (registre,
  démarrage des services, plan d'alimentation, hibernation, TRIM, DNS, applis au
  démarrage). Si tu appliques plusieurs fois, la toute première valeur est gardée.
  « Tout annuler » affiche la liste de ce qui va être remis, puis restaure tout
  à l'identique (une valeur qui n'existait pas est supprimée).
  NE PEUVENT PAS être annulés : applis supprimées (débloat, Copilot, OneDrive) ou
  installées, Edge désinstallé, fichiers temporaires effacés, réparation DISM/SFC.
  Pour ça : Système > Restaurer le système (point de restauration).



RÉGLAGES DE L'APPLI
  Animations, thème et langue sont mémorisés dans HKCU\Software\Lukzyr
  (Animations, Theme, Langue). Par défaut : animations selon Windows, thème
  sombre, langue de Windows (français sinon anglais).

SÉCURITÉ
  - Un point de restauration "Avant Lukzyr Optimisation" est créé avant de commencer.
  - Les réglages d'origine sont sauvegardés : « Tout annuler ».
  - Store, Xbox, Defender, Windows Update et pilotes ne sont jamais touchés
    (aucun pilote n'est supprimé).
  - Le journal de chaque exécution est gardé dans C:\ProgramData\Lukzyr\
    (Paramètres > À propos > « Ouvrir les journaux », ou Journal > « Ouvrir le dossier
    des journaux » ; le dossier est créé s'il n'existe pas).

TEMPÉRATURE (Matériel > Santé)
  L'appli essaie, dans l'ordre : LibreHardwareMonitor / OpenHardwareMonitor s'ils
  tournent, puis les capteurs que Windows expose (zone thermique, ACPI). Les valeurs
  impossibles (27,8 °C fixe, moins de 15 °C, plus de 115 °C) sont ignorées et la source
  est affichée sous la mesure.
  Beaucoup de PC (notamment les processeurs AMD Ryzen) ne donnent PAS leur température
  à Windows : la carte l'explique et propose « Installer LibreHardwareMonitor »
  (gratuit, open source, installé avec winget depuis le dépôt officiel, seulement si tu
  confirmes). Ensuite : ouvre LibreHardwareMonitor, Options > Remote Web Server > Run
  (port 8085), puis Actualiser dans Santé : températures processeur ET carte graphique.
  Bon à savoir : LibreHardwareMonitor utilise son propre pilote de capteurs, que
  certains antivirus (dont Defender) peuvent signaler. Lukzyr n'installe jamais de pilote
  lui-même, n'en fournit aucun et ne touche pas à l'antivirus.

CONTENU DU DOSSIER
  Lukzyr Optimisation.exe            Lance l'interface (demande les droits admin)
  LANCER - Lukzyr Optimisation.bat   Lanceur de secours
  scripts\                           Scripts PowerShell (+ Mode-console.bat sans interface,
                                     qui propose aussi le guide BIOS personnalisé)
  guides\Guide-BIOS.txt              Guide BIOS générique (secours)
  assets\lukzyr.ico                  Icône (fenêtre + exe)
  assets\logo.png                    Logo de l'en-tête
  assets\source-lanceur\             Source du lanceur .exe + Compiler-Lanceur.bat

CHANGER LE LOGO
  Le logo n'existe qu'à un seul endroit : le dossier assets.
    1. Remplace assets\logo.png (carré, 256 x 256 conseillé, fond transparent)
       et assets\lukzyr.ico (icône Windows : 16, 32, 48, 64, 128 et 256 px).
       La fenêtre et l'en-tête les utilisent directement.
    2. Pour l'icône de l'exe (elle est intégrée au fichier) : double-clique sur
       assets\source-lanceur\Compiler-Lanceur.bat. Il recompile
       « Lukzyr Optimisation.exe » avec le compilateur C# fourni avec Windows
       (.NET Framework 4, rien à installer). L'explorateur peut garder l'ancienne
       icône en cache quelques minutes.



NOUVEAUTÉS v3.1
  - Page BIOS : guide personnalisé selon la carte mère détectée (MSI, ASUS,
    Gigabyte/AORUS, ASRock, Biostar, NZXT, PC de marque et portables).
  - Avertit si la RAM tourne sous sa vitesse annoncée (XMP/EXPO désactivé).
