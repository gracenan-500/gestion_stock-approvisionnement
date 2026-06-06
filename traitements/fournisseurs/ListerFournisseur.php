<?php

require_once "../../donnees/Fournisseur.php";

$fournisseur = new Fournisseur();

header('Content-Type: application/json');

echo json_encode(
    $fournisseur->lister()
);