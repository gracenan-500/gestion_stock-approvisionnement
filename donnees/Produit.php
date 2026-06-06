<?php

require_once "Database.php";

class Produit
{
    private $connexion;

    public function __construct()
    {
        $database = new Database();
        $this->connexion = $database->getConnexion();
    }

    public function ajouter(
        $id_famille,
        $id_produit_pere,
        $code,
        $designation,
        $unite,
        $prix_achat,
        $prix_vente,
        $stock_alerte,
        $is_fractionnaire,
        $facteur_fraction
    )
    {
        $sql = "
            INSERT INTO produit
            (
                id_famille,
                id_produit_pere,
                code,
                designation,
                unite,
                prix_achat,
                prix_vente,
                stock_alerte,
                is_fractionnaire,
                facteur_fraction
            )
            VALUES
            (
                :id_famille,
                :id_produit_pere,
                :code,
                :designation,
                :unite,
                :prix_achat,
                :prix_vente,
                :stock_alerte,
                :is_fractionnaire,
                :facteur_fraction
            )
        ";

        $requete = $this->connexion->prepare($sql);

        return $requete->execute([
            ':id_famille' => $id_famille,
            ':id_produit_pere' => $id_produit_pere,
            ':code' => $code,
            ':designation' => $designation,
            ':unite' => $unite,
            ':prix_achat' => $prix_achat,
            ':prix_vente' => $prix_vente,
            ':stock_alerte' => $stock_alerte,
            ':is_fractionnaire' => $is_fractionnaire,
            ':facteur_fraction' => $facteur_fraction
        ]);
    }
}