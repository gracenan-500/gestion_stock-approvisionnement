<?php

require_once "../../donnees/Fournisseur.php";

if ($_SERVER["REQUEST_METHOD"] === "POST") {

    $nom = $_POST["nom"];
    $telephone = $_POST["telephone"];
    $email = $_POST["email"];
    $adresse = $_POST["adresse"];

    $fournisseur = new Fournisseur();

    $resultat = $fournisseur->ajouter(
        $nom,
        $telephone,
        $email,
        $adresse
    );

    if ($resultat) {
        echo "Fournisseur ajouté avec succès";
    } else {
        echo "Erreur lors de l'ajout";
    }
}