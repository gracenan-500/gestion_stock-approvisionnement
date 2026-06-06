<?php

require_once "Database.php";

class Fournisseur
{
    private $connexion;

    public function __construct()
    {
        $database = new Database();
        $this->connexion = $database->getConnexion();
    }

    public function ajouter($nom, $telephone, $email, $adresse)
    {
        $sql = "INSERT INTO fournisseur
                (nom, telephone, email, adresse)
                VALUES (:nom, :telephone, :email, :adresse)";

        $stmt = $this->connexion->prepare($sql);

        return $stmt->execute([
            ':nom' => $nom,
            ':telephone' => $telephone,
            ':email' => $email,
            ':adresse' => $adresse
        ]);
    }

    public function lister()
    {
        $sql = "SELECT * FROM fournisseur
                WHERE deleted_at IS NULL
                ORDER BY nom";

        $stmt = $this->connexion->query($sql);

        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
}